---------------------------------------------------------------------------------
-- Title         : Ethernet Layer RX
-- Project       : General Purpose Core
---------------------------------------------------------------------------------
-- File          : EthFrameRx.vhd
-- Author        : Kurtis Nishimura
---------------------------------------------------------------------------------
-- Description:
-- Connects to MAC, reads and parses Ethernet frames
---------------------------------------------------------------------------------

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.GigabitEthPkg.all;

entity EthFrameRx is 
   generic (
      GATE_DELAY_G : time := 1 ns;
      -- Maximum number of data bytes allowed per frame
      MAX_SIZE_G   : integer := 1500;
      SIZE_BITS_G  : integer := 12
   );
   port ( 
      -- 125 MHz ethernet clock in
      ethRxClk       : in sl;
      ethRxRst       : in sl := '0';
      -- Settings from the upper level
      macAddress     : in MacAddrType := MAC_ADDR_INIT_C;
      -- Incoming data from the MAC layer
      macRxData      : in slv(7 downto 0);
      macRxDataValid : in sl;
      macRxDataLast  : in sl;
      macRxBadFrame  : in sl;
      -- Outgoing data to next layer
      ethRxEtherType : out EtherType;
      ethRxSrcMac    : out MacAddrType;
      ethRxDestMac   : out MacAddrType;
      ethRxData      : out slv( 7 downto 0);
      ethRxDataValid : out sl;
      ethRxDataLast  : out sl
   ); 

end EthFrameRx;

-- Define architecture
architecture rtl of EthFrameRx is

   type StateType is (IDLE_S, 
                      DST_MAC_S, SRC_MAC_S, ETHERTYPE_S,
                      BUFFER_S, DUMP_S, DONE_S);
   type ReadStateType is (WAIT_S, READ_S);
   
   type RegType is record
      state        : StateType;
      rxDataOut    : slv(7 downto 0);
      rxDataValid  : sl;
      rxDataLast   : sl;
      rxByteCount  : slv(SIZE_BITS_G-1 downto 0);
      payloadCount : slv(SIZE_BITS_G-1 downto 0);
      rxSrcMac     : MacAddrType;
      rxDstMac     : MacAddrType;
      rxEtherType  : EtherType;
      wrEn         : sl;
      wrData       : slv(7 downto 0);
      wrAddr       : slv(SIZE_BITS_G-1 downto 0);
      startRd      : sl;
      rdState      : ReadStateType;
      rdAddr       : slv(SIZE_BITS_G-1 downto 0);
      rdCount      : slv(SIZE_BITS_G-1 downto 0);
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      state        => IDLE_S,
      rxDataOut    => (others => '0'),
      rxDataValid  => '0',
      rxDataLast   => '0',
      rxByteCount  => (others => '0'),
      payloadCount => (others => '0'),
      rxSrcMac     => MAC_ADDR_INIT_C,
      rxDstMac     => MAC_ADDR_INIT_C,
      rxEtherType  => ETH_TYPE_INIT_C,
      wrEn         => '0',
      wrData       => (others => '0'),
      wrAddr       => (others => '0'),
      startRd      => '0',
      rdState      => WAIT_S,
      rdAddr       => (others => '0'),
      rdCount      => (others => '0')
   );
   
   signal rdData : slv(7 downto 0);
   
   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;
   
   constant CRC_BYTES_C : integer := 4;
   
   -- ISE attributes to keep signals for debugging
   -- attribute keep : string;
   -- attribute keep of r : signal is "true";
   -- attribute keep of crcOut : signal is "true";      
   
   -- Vivado attributes to keep signals for debugging
   -- attribute dont_touch : string;
   -- attribute dont_touch of r : signal is "true";
   -- attribute dont_touch of crcOut : signal is "true";   
   
begin

   -- This needs to be modified to match the max payload size
   -- Size was changed to 4096 to support natural rollover!
   U_FrameBuffer : entity work.bram8x3000
      port map (
         clka   => ethRxClk,
         wea(0) => r.wrEn,
         addra  => r.wrAddr,
         dina   => r.wrData,
         clkb   => ethRxClk,
         rstb   => ethRxRst,
         addrb  => r.rdAddr,
         doutb  => rdData
      );

   comb : process(r,rdData,ethRxRst,macAddress,
                  macRxData,macRxDataValid,
                  macRxDataLast, macRxBadFrame) is
      variable v : RegType;
   begin
      v := r;

      -- Resets for pulsed outputs
      v.rxDataLast  := '0';
      v.startRd     := '0';
      
      -- State machine
      case(r.state) is 
         when IDLE_S =>
            v.rxDataOut    := (others => '0');
            v.startRd      := '0';
            v.rxByteCount  := (others => '0');
            v.wrEn         := '0';
            v.wrData       := (others => '0');
            if (macRxDataValid = '1') then
               v.rxDstMac(5) := macRxData;
               v.rxByteCount := r.rxByteCount + 1;
               v.state       := DST_MAC_S;
            end if;
         when DST_MAC_S =>
            if (macRxBadFrame = '1' or macRxDataLast = '1') then
               v.state := IDLE_S;
            elsif (macRxDataValid = '1') then
               v.rxDstMac( 5-conv_integer(r.rxByteCount) ) := macRxData;
               v.rxByteCount                               := r.rxByteCount + 1;
               if (r.rxByteCount = 5) then
                  v.rxByteCount := (others => '0');
                  v.state       := SRC_MAC_S;
               end if;
            end if;
         when SRC_MAC_S =>
            if (macRxBadFrame = '1' or macRxDataLast = '1') then
               v.state := IDLE_S;
            elsif (r.rxDstMac /= macAddress and 
                   r.rxDstMac /= MAC_ADDR_BCAST_C) then
               v.state := DUMP_S;
            elsif (macRxDataValid = '1') then
               v.rxSrcMac( 5-conv_integer(r.rxByteCount) ) := macRxData;
               v.rxByteCount                             := r.rxByteCount + 1;
               if (r.rxByteCount = 5) then
                  v.rxByteCount := (others => '0');
                  v.state       := ETHERTYPE_S;
               end if;
            end if;
         when ETHERTYPE_S =>
            if (macRxBadFrame = '1' or macRxDataLast = '1') then
               v.state := IDLE_S;
            elsif (macRxDataValid = '1') then
               v.rxEtherType( (2-conv_integer(r.rxByteCount))*8 - 1 downto (1-conv_integer(r.rxByteCount))*8 ) := macRxData;
               v.rxByteCount                                                                                   := r.rxByteCount + 1;
               if (r.rxByteCount = 1) then
                  v.rxByteCount  := (others => '0');
                  v.payloadCount := (others => '0');
                  v.state        := BUFFER_S;
               end if;
            end if;
         when BUFFER_S =>
            if (macRxBadFrame = '1') then
               v.state := IDLE_S;
            elsif (r.rxEtherType /= ETH_TYPE_IPV4_C and
                   r.rxEtherType /= ETH_TYPE_ARP_C) then
               v.state := DUMP_S;
            elsif (macRxDataLast = '1') then
               v.startRd := '1';
               v.state   := IDLE_S;
            end if;

            v.wrData := macRxData;            
            if (macRxDataValid = '1') then
               v.wrEn         := macRxDataValid;
               v.wrAddr       := r.wrAddr + 1;
               v.payloadCount := r.payloadCount + 1;
            end if;
            
         when DUMP_S   =>
            if (macRxDataLast = '1') then
               v.state := IDLE_S;
            end if;
         when others =>
            v.state := IDLE_S;
      end case;

      -- Separate state machine for reading ring buffer
      case (r.rdState) is
         when WAIT_S =>
            v.rxDataValid  := '0';
            v.rdAddr       := (others => '0');
            v.rdCount      := (others => '0');
            if (r.startRd = '1') then
               v.rdAddr  := r.wrAddr - r.payloadCount + 1;
               v.rdCount := r.payloadCount - CRC_BYTES_C - 1;
               v.rdState := READ_S;
            end if;
         when READ_S =>
            v.rxDataValid := '1';
            v.rdAddr      := r.rdAddr + 1;
            v.rdCount     := r.rdCount - 1;
            if (r.rdCount = 0) then
               v.rxDataLast := '1';
               v.rdState    := WAIT_S;
            end if;
         when others =>
            v.rdState := WAIT_S;
      end case;
      
      -- Reset logic
      if (ethRxRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Outputs to ports
      ethRxEtherType  <= r.rxEtherType;
      ethRxSrcMac     <= r.rxSrcMac;
      ethRxDestMac    <= r.rxDstMac;
      ethRxData       <= rdData;
      ethRxDataValid  <= r.rxDataValid;
      ethRxDataLast   <= r.rxDataLast;
      
      -- Assignment of combinatorial variable to signal
      rin <= v;

   end process;

   seq : process (ethRxClk) is
   begin
      if (rising_edge(ethRxClk)) then
         r <= rin after GATE_DELAY_G;
      end if;
   end process seq;   

end rtl;

