---------------------------------------------------------------------------------
-- Title         : IPv4 Packet RX
-- Project       : General Purpose Core
---------------------------------------------------------------------------------
-- File          : IPv4Rx.vhd
-- Author        : Kurtis Nishimura
---------------------------------------------------------------------------------
-- Description:
-- Connects to Ethernet layer, reads incoming IPv4 packets
---------------------------------------------------------------------------------

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.GigabitEthPkg.all;

entity IPv4Rx is 
   generic (
      GATE_DELAY_G   : time := 1 ns
   );
   port ( 
      -- 125 MHz ethernet clock in
      ethRxClk        : in sl;
      ethRxRst        : in sl := '0';
      -- Incoming data from Ethernet frame
      ethRxData       : in  slv( 7 downto 0);
      ethRxDataValid  : in  sl;
      ethRxDataLast   : in  sl;
      -- Data from the IPv4 header
      ipLength        : out slv(15 downto 0);
      ipId            : out slv(15 downto 0);
      ipMoreFragments : out sl;
      ipFragOffset    : out slv(12 downto 0);
      ipTtl           : out slv( 7 downto 0);
      ipProtocol      : out slv( 7 downto 0);
      ipSrcAddr       : out IpAddrType;
      ipDstAddr       : out IpAddrType;
      -- Actual data from the payload
      ipData          : out slv(31 downto 0);
      ipDataValid     : out sl;
      ipDataLast      : out sl
   ); 
end IPv4Rx;

-- Define architecture
architecture rtl of IPv4Rx is

   type ReadStateType is (WAIT_S, READ_S);
   type StateType     is (IDLE_S, 
                          HEADER_1_S, HEADER_2_S, HEADER_3_S, HEADER_4_S, 
                          HEADER_OPTIONS_S,
                          PAYLOAD_S, 
                          DUMP_S);
   
   type RegType is record
      state           : StateType;
      readState       : ReadStateType;
      readCnt         : slv( 1 downto 0);
      data8           : slv( 7 downto 0);
      data8Valid      : sl;
      data8Last       : sl;
      data32          : slv(31 downto 0);
      data32Valid     : sl;
      data32Last      : sl;
      headerLength    : slv( 3 downto 0);
      packetLength    : slv(15 downto 0);
      packetId        : slv(15 downto 0);
      ipMoreFragments : sl;
      ipFragOffset    : slv(12 downto 0);
      ipTimeToLive    : slv( 7 downto 0);
      ipProtocol      : slv( 7 downto 0);
      ipChecksum      : slv(31 downto 0);
      ipSrcAddr       : IpAddrType;
      ipDstAddr       : IpAddrType;
      ipData          : slv(31 downto 0);
      ipDataValid     : sl;
      ipDataLast      : sl;
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      state           => IDLE_S,
      readState       => WAIT_S,
      readCnt         => (others => '0'),
      data8           => (others => '0'),
      data8Valid      => '0',
      data8Last       => '0',
      data32          => (others => '0'),
      data32Valid     => '0',
      data32Last      => '0',
      headerLength    => (others => '0'),
      packetLength    => (others => '0'),
      packetId        => (others => '0'),
      ipMoreFragments => '0',
      ipFragOffset    => (others => '0'),
      ipTimeToLive    => (others => '0'),
      ipProtocol      => (others => '0'),
      ipChecksum      => (others => '0'),
      ipSrcAddr       => IP_ADDR_INIT_C,
      ipDstAddr       => IP_ADDR_INIT_C,
      ipData          => (others => '0'),
      ipDataValid     => '0',
      ipDataLast      => '0'
   );
   
   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   -- ISE attributes to keep signals for debugging
   -- attribute keep : string;
   -- attribute keep of r : signal is "true";
   -- attribute keep of crcOut : signal is "true";      
   
   -- Vivado attributes to keep signals for debugging
   -- attribute dont_touch : string;
   -- attribute dont_touch of r : signal is "true";
   -- attribute dont_touch of crcOut : signal is "true";   
   
begin

   comb : process(r,ethRxRst,ethRxData,ethRxDataValid,ethRxDataLast) is
      variable v : RegType;
   begin
      v := r;

      -- Resets for pulsed outputs
      v.data32valid := '0';
      
      -- Register incoming data
      v.data8       := ethRxData;
      v.data8Valid  := ethRxDataValid;
      v.data8Last   := ethRxDataLast;
      v.data32Valid := '0';
      v.data32Last  := '0';

      -- State machine for 8-to-32 translation
      case(r.readState) is 
         when WAIT_S =>
            v.readCnt     := (others => '1');
            v.data32      := (others => '0');
            v.data32Valid := '0';
            v.data32Last  := '0';
            if ethRxDataValid = '1' then
               v.readState := READ_S;
            end if;
         when READ_S =>
            if r.data8Valid = '1' then
               v.data32( (1+conv_integer(r.readCnt))*8-1 downto (conv_integer(r.readCnt))*8) := r.data8;
               v.readCnt := r.readCnt - 1;
               if r.readCnt = 0 then
                  v.data32Valid := '1';
               end if;
               -- Force a valid on data8Last, in case we have 
               -- non-4-byte divisible data.
               if r.data8Last = '1' then
                  if r.readCnt > 0 then
                     v.data32(conv_integer(r.readCnt) * 8 - 1 downto 0) := (others => '0'); 
                  end if;
                  v.data32Valid := '1';
                  v.data32Last  := '1';
                  v.readState   := WAIT_S;
               end if;
            end if;
         when others =>
            v.readState := WAIT_S;
      end case;

      -- Reset pulsed signals
      v.ipDataValid := '0';
      v.ipDataLast  := '0';
      
      -- State machine for interpreting 32-bit data
      case(r.state) is 
         -- VERSION, IHL, DSCP, ECN, LENGTH
         when IDLE_S =>
            v.ipChecksum := (others => '0');
            if r.data32Valid = '1' then
               v.ipChecksum := conv_std_logic_vector(conv_integer(r.data32(31 downto 16)) + conv_integer(r.data32(15 downto 0)),32);
               if (r.data32(31 downto 28) /= IPV4_VERSION_C or 
                   r.data32(23 downto 16) /= IPV4_DSCP_C & IPV4_ECN_C) then
                  v.state := DUMP_S;
               else
                  v.headerLength := r.data32(27 downto 24);
                  v.packetLength := r.data32(15 downto  0);
                  v.state        := HEADER_1_S;               
               end if;
            end if;
         -- ID, FLAGS, FRAGMENT OFFSET
         when HEADER_1_S => 
            if r.data32Valid = '1' then
               v.ipChecksum      := conv_std_logic_vector(conv_integer(r.ipChecksum(31 downto 16)) + conv_integer(r.ipChecksum(15 downto 0)) + conv_integer(r.data32(31 downto 16)) + conv_integer(r.data32(15 downto 0)),32);
               v.packetId        := r.data32(31 downto 16);
               v.ipMoreFragments := r.data32(13);
               v.ipFragOffset    := r.data32(12 downto 0);
               v.state           := HEADER_2_S;
            end if;
         -- TTL, PROTOCOL, HEADER CHECKSUM
         when HEADER_2_S =>  
            if r.data32Valid = '1' then
               v.ipChecksum   := conv_std_logic_vector(conv_integer(r.ipChecksum(31 downto 16)) + conv_integer(r.ipChecksum(15 downto 0)) + conv_integer(r.data32(31 downto 16)) + conv_integer(r.data32(15 downto 0)),32);
               v.ipTimeToLive := r.data32(31 downto 24);
               v.ipProtocol   := r.data32(23 downto 16);
               v.state        := HEADER_3_S;
            end if;
         -- SOURCE IP
         when HEADER_3_S =>
            if r.data32Valid = '1' then
               v.ipChecksum   := conv_std_logic_vector(conv_integer(r.ipChecksum(31 downto 16)) + conv_integer(r.ipChecksum(15 downto 0)) + conv_integer(r.data32(31 downto 16)) + conv_integer(r.data32(15 downto 0)),32);
               v.ipSrcAddr(3) := r.data32(31 downto 24);
               v.ipSrcAddr(2) := r.data32(23 downto 16);
               v.ipSrcAddr(1) := r.data32(15 downto  8);
               v.ipSrcAddr(0) := r.data32( 7 downto  0);
               v.state        := HEADER_4_S;
            end if;
         -- DESTINATION IP
         when HEADER_4_S =>
            if r.data32Valid = '1' then
               v.ipChecksum   := conv_std_logic_vector(conv_integer(r.ipChecksum(31 downto 16)) + conv_integer(r.ipChecksum(15 downto 0)) + conv_integer(r.data32(31 downto 16)) + conv_integer(r.data32(15 downto 0)),32);
               v.ipDstAddr(3) := r.data32(31 downto 24);
               v.ipDstAddr(2) := r.data32(23 downto 16);
               v.ipDstAddr(1) := r.data32(15 downto  8);
               v.ipDstAddr(0) := r.data32( 7 downto  0);
               if r.headerLength > 5 then
                  v.headerLength := r.headerLength - 5 - 1;
                  v.state        := HEADER_OPTIONS_S;
               else
                  if conv_std_logic_vector(conv_integer(v.ipChecksum(31 downto 16)) + conv_integer(v.ipChecksum(15 downto 0)),32)(15 downto 0) = x"FFFF" then
                     v.state := PAYLOAD_S;
                  else
                     v.state := DUMP_S;
                  end if;
               end if;
            end if;
         -- HEADER OPTIONS
         when HEADER_OPTIONS_S => 
            if r.data32Valid = '1' then
               v.ipChecksum   := conv_std_logic_vector(conv_integer(r.ipChecksum(31 downto 16)) + conv_integer(r.ipChecksum(15 downto 0)) + conv_integer(r.data32(31 downto 16)) + conv_integer(r.data32(15 downto 0)),32);
               if r.headerLength = 0 then
                  if conv_std_logic_vector(conv_integer(v.ipChecksum(31 downto 16)) + conv_integer(v.ipChecksum(15 downto 0)),16)(15 downto 0) = x"FFFF" then
                     v.state := PAYLOAD_S;
                  else
                     v.state := DUMP_S;
                  end if;
               end if;
               v.headerLength := r.headerLength - 1;
            end if;
         -- PAYLOAD DATA
         when PAYLOAD_S =>
            if r.data32Valid = '1' then
               v.ipData      := r.data32;
               v.ipDataValid := r.data32Valid;
               v.ipDataLast  := r.data32Last;
               if r.data32Last = '1' then
                  v.state := IDLE_S;
               end if;
            end if;
         -- DUMP
         when DUMP_S =>
            if r.data32Last = '1' then
               v.state := IDLE_S;
            end if;
         -- Others
         when others =>
            v.state := IDLE_S;
      end case;


      -- Reset logic
      if (ethRxRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Outputs to ports
      ipLength        <= r.packetLength;
      ipId            <= r.packetId;
      ipMoreFragments <= r.ipMoreFragments;
      ipFragOffset    <= r.ipFragOffset;
      ipTtl           <= r.ipTimeToLive;
      ipProtocol      <= r.ipProtocol;
      ipSrcAddr       <= r.ipSrcAddr;
      ipDstAddr       <= r.ipDstAddr;
      ipData          <= r.ipData;
      ipDataValid     <= r.ipDataValid;
      ipDataLast      <= r.ipDataLast;
      
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

