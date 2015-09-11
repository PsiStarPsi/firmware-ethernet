---------------------------------------------------------------------------------
-- Title         : 1000 BASE X MAC RX Layer
-- Project       : General Purpose Core
---------------------------------------------------------------------------------
-- File          : Eth1000BaseXMacRx.vhd
-- Author        : Kurtis Nishimura
---------------------------------------------------------------------------------
-- Description:
-- Connects to GTP interface to 1000 BASE X Ethernet.
-- Receiver passes bytes out.
---------------------------------------------------------------------------------

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.Eth1000BaseXPkg.all;
use work.GigabitEthPkg.all;


entity Eth1000BaseXMacRx is 
   generic (
      GATE_DELAY_G : time := 1 ns
   );
   port ( 
      -- 125 MHz ethernet clock in
      ethRxClk       : in sl;
      ethRxRst       : in sl := '0';
      -- Incoming data from the 16-to-8 mux
      macDataIn      : in EthMacDataType;
      -- Outgoing bytes and flags to the applications
      macRxData      : out slv(7 downto 0);
      macRxDataValid : out sl;
      macRxDataLast  : out sl;
      macRxBadFrame  : out sl;
      -- Monitoring flags
      macBadCrcCount : out slv(15 downto 0)
   ); 

end Eth1000BaseXMacRx;

-- Define architecture
architecture rtl of Eth1000BaseXMacRx is

   type StateType is (S_IDLE, S_PREAMBLE, S_FRAME_DATA, S_WAIT_CRC, 
                      S_CHECK_CRC);
   
   type RegType is record
      state        : StateType;
      rxDataValid  : sl;
      rxDataLast   : sl;
      rxDataOut    : slv(7 downto 0);
      rxBadFrame   : sl;
      crcReset     : sl;
      crcDataValid : sl;
      byteCount    : slv(15 downto 0);
      badCrcCount  : slv(15 downto 0);
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      state        => S_IDLE,
      rxDataOut    => (others => '0'),
      rxDataValid  => '0',
      rxDataLast   => '0',
      rxBadFrame   => '0',
      crcReset     => '0',
      crcDataValid => '0',
      byteCount    => (others => '0'),
      badCrcCount  => (others => '0')
   );
   
   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   signal crcOut       : slv(31 downto 0);
--   signal crcData      : slv(31 downto 0);
   signal crcDataWidth : slv(2 downto 0);

   -- ISE attributes to keep signals for debugging
   -- attribute keep : string;
   -- attribute keep of r : signal is "true";
   -- attribute keep of crcOut : signal is "true";      
   
   -- Vivado attributes to keep signals for debugging
   -- attribute dont_touch : string;
   -- attribute dont_touch of r : signal is "true";
   -- attribute dont_touch of crcOut : signal is "true";   
   
begin

--   crcData      <= x"000000" & r.rxDataOut;
   crcDataWidth <= "000";

   U_Crc32 : entity work.Crc32
      generic map (
         BYTE_WIDTH_G => 1,
         CRC_INIT_G   => x"FFFFFFFF",
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map (
         crcOut        => crcOut,
         crcClk        => ethRxClk,
         crcDataValid  => r.crcDataValid,
         crcDataWidth  => crcDataWidth,
         crcIn         => r.rxDataOut,
         crcReset      => r.crcReset
      );

   comb : process(r,macDataIn,ethRxRst,crcOut) is
      variable v : RegType;
   begin
      v := r;

      v.rxDataOut   := macDataIn.data;
      
      case(r.state) is 
         when S_IDLE =>
            v.crcReset     := '1';
            v.crcDataValid := '0';
            v.rxDataValid  := '0';
            v.rxDataLast   := '0';
            v.rxBadFrame   := '0';
            v.byteCount    := (others => '0');
            -- If we see start of packet then we should move on to accept preamble
            if (macDataIn.dataValid = '1' and macDataIn.dataK = '1' and macDataIn.data = K_SOP_C) then
               v.state := S_PREAMBLE;
            end if;
         when S_PREAMBLE =>
            v.crcReset := '0';
            if (macDataIn.dataValid = '1' and macDataIn.dataK = '0' and macDataIn.data = ETH_SOF_C) then
               v.state := S_FRAME_DATA;
            -- Bail out if we see a comma, error, carrier
            elsif (macDataIn.dataValid = '1' and macDataIn.dataK = '1'  and
                   (macDataIn.data = K_COM_C or macDataIn.data = K_EOP_C or macDataIn.data = K_CAR_C or macDataIn.data = K_ERR_C)) then
               v.state := S_IDLE;
            end if;
         when S_FRAME_DATA =>
            v.rxDataValid  := macDataIn.dataValid;
            v.crcDataValid := '1';
            v.byteCount    := r.byteCount + 1;
            -- Possible errors: K_ERR_C, misplaced comma (K_COM_C)
            if (macDataIn.dataValid = '1' and macDataIn.dataK = '1' and 
                (macDataIn.data = K_ERR_C or macDataIn.data = K_COM_C)) then
               v.rxDataValid := '0';
               v.rxBadFrame  := '1';
               v.rxDataLast  := '1';
               v.state       := S_IDLE;
            -- Otherwise, should be frame data until we see end of packet
            elsif (macDataIn.dataValid = '1' and macDataIn.dataK = '1' and macDataIn.data = K_EOP_C) then
               v.rxDataValid  := '0';
               v.crcDataValid := '0';
               v.state        := S_WAIT_CRC;
            end if;
         -- Wait one cycle to account for latency of the CRC module
         when S_WAIT_CRC =>
            v.state := S_CHECK_CRC;
         -- Check whether the CRC is valid
         when S_CHECK_CRC =>
            v.rxDataLast  := '1';
            -- Check for packet length and valid CRC
            if (crcOut = CRC_CHECK_C and r.byteCount >= 46) then
               v.rxBadFrame  := '0';
            -- Otherwise, it's a bad frame
            else
               v.rxBadFrame  := '1';
               v.badCrcCount := r.badCrcCount + 1;
            end if;
            v.state := S_IDLE;
         when others =>
            v.state := S_IDLE;
      end case;
      
      -- Reset logic
      if (ethRxRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Outputs to ports
      macRxData      <= r.rxDataOut;
      macRxDataValid <= r.rxDataValid;
      macRxDataLast  <= r.rxDataLast;
      macRxBadFrame  <= r.rxBadFrame;
      macBadCrcCount <= r.badCrcCount;
      
      rin <= v;

   end process;

   seq : process (ethRxClk) is
   begin
      if (rising_edge(ethRxClk)) then
         r <= rin after GATE_DELAY_G;
      end if;
   end process seq;   

end rtl;

