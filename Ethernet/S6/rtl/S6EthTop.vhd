----------------------------------------------------------------------------------
-- Company: 
-- Engineer:  
-- 
-- Create Date:    13:21:31 07/23/2015 
-- Design Name: 
-- Module Name:    S6EthTop - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
--use IEEE.NUMERIC_STD.ALL;
use work.UtilityPkg.all;
use work.Eth1000BaseXPkg.all;
use work.GigabitEthPkg.all;

library UNISIM;
use UNISIM.VComponents.all;

entity S6EthTop is
   generic (
      NUM_IP_G        : integer := 2;
      GATE_DELAY_G    : time    := 1 ns
   );
   port ( 
      -- Direct GT connections
      gtTxP           : out sl;
      gtTxN           : out sl;
      gtRxP           :  in sl;
      gtRxN           :  in sl;
      gtClkP          :  in sl;
      gtClkN          :  in sl;
      -- Alternative clock input from fabric
      fabClkIn        :  in sl := '0';
      -- SFP transceiver disable pin
      txDisable       : out sl;
      -- Clocks out from Ethernet core
      ethUsrClk62     : out sl;
      ethUsrClk125    : out sl;
      -- Status and diagnostics out
      ethSync         : out  sl;
      ethReady        : out  sl;
      led             : out  slv(15 downto 0);
      -- Core settings in 
      macAddr         : in  MacAddrType := MAC_ADDR_DEFAULT_C;
      ipAddrs         : in  IpAddrArray(NUM_IP_G-1 downto 0) := (others => IP_ADDR_DEFAULT_C);
      udpPorts        : in  Word16Array(NUM_IP_G-1 downto 0) := (others => (others => '0'));
      -- User clock inputs
      userClk         : in  sl;
      userRstIn       : in  sl;
      userRstOut      : out sl;
      -- User data interfaces
      userTxData      : in  Word32Array(NUM_IP_G-1 downto 0);
      userTxDataValid : in  slv(NUM_IP_G-1 downto 0);
      userTxDataLast  : in  slv(NUM_IP_G-1 downto 0);
      userTxDataReady : out slv(NUM_IP_G-1 downto 0);
      userRxData      : out Word32Array(NUM_IP_G-1 downto 0);
      userRxDataValid : out slv(NUM_IP_G-1 downto 0);
      userRxDataLast  : out slv(NUM_IP_G-1 downto 0);
      userRxDataReady : in  slv(NUM_IP_G-1 downto 0)
   );
end S6EthTop;

architecture Behavioral of S6EthTop is

   signal fabClk       : sl;
   signal fabClkRst    : sl;
   signal gtClk        : sl;
   signal ethClk62     : sl;
   signal ethClk62Rst  : sl;
   signal ethClk125    : sl;
   signal ethClk125Rst : sl;

   signal dcmClkValid   : sl;
   signal dcmSpLocked   : sl;
   signal usrClkValid   : sl;
   signal usrClkLocked  : sl;
   signal pllLock0      : sl;
   signal gtpResetDone0 : sl;

   signal gtpReset0     : sl;
   signal gtpReset1     : sl;
   signal txReset0      : sl;
   signal txReset1      : sl;
   signal rxReset0      : sl;
   signal rxReset1      : sl;
   signal rxBufReset0   : sl;
   signal rxBufReset1   : sl;

   signal rxBufStatus0  : slv(2 downto 0);
   signal rxBufStatus1  : slv(2 downto 0);
   signal txBufStatus0  : slv(1 downto 0);
   signal txBufStatus1  : slv(1 downto 0);
   signal rxBufError0   : sl;
   signal rxBufError1   : sl;

   signal rxByteAligned0   : sl;
   signal rxByteAligned1   : sl;
   signal rxEnMCommaAlign0 : sl;
   signal rxEnMCommaAlign1 : sl;
   signal rxEnPCommaAlign0 : sl;
   signal rxEnPCommaAlign1 : sl;

   signal ethRxLinkSync  : sl;
   signal ethAutoNegDone : sl;

   signal phyRxLaneIn    : EthRxPhyLaneInType;
   signal phyTxLaneOut   : EthTxPhyLaneOutType;
   
   signal tpData      : slv(31 downto 0);
   signal tpDataValid : sl;
   signal tpDataLast  : sl;
   signal tpDataReady : sl;

   signal userRst     : sl;
   
begin

   txDisable         <= '0';
   ethSync           <= ethRxLinkSync;
   ethReady          <= ethAutoNegDone;
   ethUsrClk62       <= ethClk62;
   ethUsrClk125      <= ethClk125;
   userRstOut        <= userRst;
   
   led(0)            <= dcmSpLocked;
   led(1)            <= dcmClkValid;
   led(2)            <= not(gtpReset0);
   led(3)            <= gtpResetDone0;
   led(4)            <= pllLock0;
   led(5)            <= usrClkLocked;
   led(6)            <= usrClkValid;
   led(7)            <= ethRxLinkSync;
   led(8)            <= ethAutoNegDone;
   led(9)            <= not(ethClk62Rst);
   led(10)           <= not(ethClk125Rst);
   led(15 downto 11) <= (others => '1');

   fabClk <= fabClkIn;
   U_IBUFDS  : IBUFDS  port map ( I => gtClkP,  IB => gtClkN,  O => gtClk);

   U_GtpS6 : entity work.GtpS6
      generic map (
         -- Reference clock selection --
         -- 000: CLK00/CLK01 selected
         -- 001: GCLK00/GCLK01 selected
         -- 010: PLLCLK00/PLLCLK01 selected
         -- 011: CLKINEAST0/CLKINEAST0 selected
         -- 100: CLK10/CLK11 selected
         -- 101: GCLK10/GCLK11 selected
         -- 110: PLLCLK10/PLLCLK11 selected
         -- 111: CLKINWEST0/CLKINWEST1 selected 
         REF_SEL_PLL0_G => "001",
         REF_SEL_PLL1_G => "001"
      )
      port map (
         -- Clocking & reset 
         gtpClkIn      => fabClk,
         gtpReset0     => gtpReset0,
         gtpReset1     => gtpReset1,
         txReset0      => txReset0,
         txReset1      => txReset1,
         rxReset0      => rxReset0,
         rxReset1      => rxReset1,
         rxBufReset0   => rxBufReset0,
         rxBufReset1   => rxBufReset1,
         -- User clock out
         usrClkOut     => ethClk62,
         usrClkX2Out   => ethClk125,
         -- DCM clocking
         dcmClkValid   => dcmClkValid,
         dcmSpLocked   => dcmSpLocked,
         usrClkValid   => usrClkValid,
         usrClkLocked  => usrClkLocked,
         -- General status outputs
         pllLock0      => pllLock0,
         pllLock1      => open,
         gtpResetDone0 => gtpResetDone0,
         gtpResetDone1 => open,
         -- Input signals (raw) 
         gtpRxP0       => gtRxP,
         gtpRxN0       => gtRxN,
         gtpTxP0       => gtTxP,
         gtpTxN0       => gtTxN,
         gtpRxP1       => '0',
         gtpRxN1       => '0',
         gtpTxP1       => open,
         gtpTxN1       => open,
         -- Data interfaces
         rxDataOut0    => phyRxLaneIn.data,
         rxDataOut1    => open,
         txDataIn0     => phyTxLaneOut.data,
         txDataIn1     => (others => '0'),
         -- RX status
         rxCharIsComma0   => open,
         rxCharIsComma1   => open,
         rxCharIsK0       => phyRxLaneIn.dataK,
         rxCharIsK1       => open,
         rxDispErr0       => phyRxLaneIn.dispErr, -- out slv(1 downto 0);
         rxDispErr1       => open, -- out slv(1 downto 0);
         rxNotInTable0    => phyRxLaneIn.decErr, -- out slv(1 downto 0);
         rxNotInTable1    => open, -- out slv(1 downto 0);
         rxRunDisp0       => open, -- out slv(1 downto 0);
         rxRunDisp1       => open, -- out slv(1 downto 0);
         rxClkCor0        => open, -- out slv(2 downto 0);
         rxClkCor1        => open, -- out slv(2 downto 0);
         rxByteAligned0   => rxByteAligned0, -- out std_logic;
         rxByteAligned1   => rxByteAligned1, -- out std_logic;
         rxEnMCommaAlign0 => rxEnMCommaAlign0, --  in std_logic;
         rxEnMCommaAlign1 => rxEnMCommaAlign1, --  in std_logic;
         rxEnPCommaAlign0 => rxEnPCommaAlign0, --  in std_logic;
         rxEnPCommaAlign1 => rxEnPCommaAlign1, --  in std_logic;
         rxBufStatus0     => rxBufStatus0, -- out slv(2 downto 0);
         rxBufStatus1     => rxBufStatus1, -- out slv(2 downto 0);
         -- TX status
         txCharDispMode0  => "00", --  in slv(1 downto 0) := "00";
         txCharDispMode1  => "00", --  in slv(1 downto 0) := "00";
         txCharDispVal0   => "00", --  in slv(1 downto 0) := "00";
         txCharDispVal1   => "00", --  in slv(1 downto 0) := "00";
         txCharIsK0       => phyTxLaneOut.dataK, --  in slv(1 downto 0);
         txCharIsK1       => "00", --  in slv(1 downto 0);
         txRunDisp0       => open, -- out slv(1 downto 0);
         txRunDisp1       => open, -- out slv(1 downto 0);
         txBufStatus0     => txBufStatus0, -- out slv(1 downto 0);
         txBufStatus1     => txBufStatus1, -- out slv(1 downto 0);
         -- Loopback settings
         loopbackIn0      => "000", -- :  in slv(2 downto 0) := "000";
         loopbackIn1      => "000"  -- :  in slv(2 downto 0) := "000"; 
      );

   -- Simple comma alignment
   rxEnMCommaAlign0 <= not(rxByteAligned0);
   rxEnPCommaAlign0 <= not(rxByteAligned0);
   rxEnMCommaAlign1 <= not(rxByteAligned1);
   rxEnPCommaAlign1 <= not(rxByteAligned1);

   -- Reset sequencing, as per UG386, Table 2-14
   -- Not all resets are implemented, only those for the functionality
   -- we care about.
   --
   -- 1. Perform GTP reset after turning on the reference clock
   U_GtpReset0 : entity work.SyncBit
      port map (
         clk      => fabClk,
         rst      => not(dcmClkValid),
         asyncBit => '0',
         syncBit  => gtpReset0
      );
   gtpReset1 <= gtpReset0;
   -- 2. Assert rxReset and txReset when usrClk, usrClk2 is not stable
   -- 3. txReset should be asserted on tx Buffer over/underflow
   U_RxReset0 : entity work.SyncBit
      generic map (
         INIT_STATE_G => '1'
      )
      port map (
         clk      => fabClk,
         rst      => not(usrClkValid) or not(dcmClkValid),
         asyncBit => '0',
         syncBit  => rxReset0
      );
   rxReset1 <= rxReset0;
   U_TxReset0 : entity work.SyncBit
      generic map (
         INIT_STATE_G => '1'
      )
      port map (
         clk      => fabClk,
         rst      => not(usrClkValid) or txBufStatus0(1),
         asyncBit => '0',
         syncBit  => txReset0
      );
   U_TxReset1 : entity work.SyncBit
      generic map (
         INIT_STATE_G => '1'
      )
      port map (
         clk      => fabClk,
         rst      => not(usrClkValid) or txBufStatus1(1),
         asyncBit => '0',
         syncBit  => txReset1
      );
   -- 4. rxBufReset should be asserted on rx buffer over/underflow 
   rxBufError0 <= '1' when rxBufStatus0 = "101" or rxBufStatus0 = "110" else '0';
   U_RxBufReset0 : entity work.SyncBit
      generic map (
         INIT_STATE_G => '1'
      )
      port map (
         clk      => fabClk,
         rst      => rxBufError0, 
         asyncBit => '0',
         syncBit  => rxBufReset0
      );
   rxBufError1 <= '1' when rxBufStatus1 = "101" or rxBufStatus1 = "110" else '0';
   U_RxBufReset1 : entity work.SyncBit
      generic map (
         INIT_STATE_G => '1'
      )
      port map (
         clk      => fabClk,
         rst      => rxBufError1, 
         asyncBit => '0',
         syncBit  => rxBufReset1
      );

   --------------------------------
   -- Gigabit Ethernet Interface --
   --------------------------------
   U_Eth1000BaseXCore : entity work.Eth1000BaseXCore
      generic map (
         NUM_IP_G        => NUM_IP_G,
         MTU_SIZE_G      => 1500,
         LITTLE_ENDIAN_G => true,
         EN_AUTONEG_G    => true,
         GATE_DELAY_G    => GATE_DELAY_G
      )
      port map ( 
         -- 125 MHz clock and reset
         eth125Clk          => ethClk125,
         eth125Rst          => ethClk125Rst,
         -- 62 MHz clock and reset
         eth62Clk           => ethClk62,
         eth62Rst           => ethClk62Rst,
         -- Addressing
         macAddr            => macAddr,
         ipAddrs            => ipAddrs,
         udpPorts           => udpPorts,
         -- Data to/from GT
         phyRxData          => phyRxLaneIn,
         phyTxData          => phyTxLaneOut,
         -- Status signals
         statusSync         => ethRxLinkSync,
         statusAutoNeg      => ethAutoNegDone,
         -- User clock and reset
         userClk            => userClk,
         userRst            => userRst,
         -- User data
         userTxData         => userTxData,
         userTxDataValid    => userTxDataValid,
         userTxDataLast     => userTxDataLast,
         userTxDataReady    => userTxDataReady,
         userRxData         => userRxData,
         userRxDataValid    => userRxDataValid,
         userRxDataLast     => userRxDataLast,
         userRxDataReady    => userRxDataReady
      );
      
   ---------------------------------------------------------------------------
   -- Resets
   ---------------------------------------------------------------------------
   -- Generate stable reset signal
   U_PwrUpRst : entity work.InitRst
      generic map (
         RST_CNT_G    => 25000000,
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map (
         clk     => fabClk,
         syncRst => fabClkRst
      );
   -- Synchronize the reset to the 125 MHz domain
   U_RstSync125 : entity work.SyncBit
      generic map (
         INIT_STATE_G    => '1',
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map (
         clk      => ethClk125,
         rst      => '0',
         asyncBit => ethClk62Rst,
         syncBit  => ethClk125Rst
      );
   -- Synchronize the reset to the 62 MHz domain
   U_RstSync62 : entity work.SyncBit
      generic map (
         INIT_STATE_G    => '1',
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map (
         clk      => ethClk125,
         rst      => '0',
         asyncBit => fabClkRst,
         syncBit  => ethClk62Rst
      );
   -- User reset
   U_RstSyncUser : entity work.SyncBit
      generic map (
         INIT_STATE_G    => '1',
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map (
         clk      => ethClk125,
         rst      => '0',
         asyncBit => ethClk62Rst or not(ethAutoNegDone) or userRstIn,
         syncBit  => userRst
      );

         
end Behavioral;

