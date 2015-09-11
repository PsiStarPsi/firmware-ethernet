--------------------------------------------------------------------------------
-- Company: 
-- Engineer:
--
-- Create Date:   00:36:20 08/28/2015
-- Design Name:   
-- Module Name:   C:/Users/Kurtis/Google Drive/mTC/svn/src/Ethernet/General/sim/IPv4Test.vhd
-- Project Name:  ethernet
-- Target Device:  
-- Tool versions:  
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: IPv4Tx
-- 
-- Dependencies:
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
-- Notes: 
-- This testbench has been automatically generated using types std_logic and
-- std_logic_vector for the ports of the unit under test.  Xilinx recommends
-- that these types always be used for the top-level I/O of a design in order
-- to guarantee that the testbench will bind correctly to the post-implementation 
-- simulation model.
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.GigabitEthPkg.all;
use work.Eth1000BaseXPkg.all;
 
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--USE ieee.numeric_std.ALL;
 
ENTITY CoreTwoIpDataSim IS
END CoreTwoIpDataSim;
 
ARCHITECTURE behavior OF CoreTwoIpDataSim IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT IPv4Tx
    PORT(
         ethTxClk : IN  std_logic;
         ethTxRst : IN  std_logic;
         ipPacketLength : IN  std_logic_vector(15 downto 0);
         ipPacketId : IN  std_logic_vector(15 downto 0);
         ipMoreFragments : IN  std_logic;
         ipFragOffset : IN  std_logic_vector(12 downto 0);
         ipProtocol : IN  std_logic_vector(7 downto 0);
         ipSrcAddr : IN  IpAddrType;
         ipDstAddr : IN  IpAddrType;
         ipData : IN  std_logic_vector(31 downto 0);
         ipDataValid : IN  std_logic;
         ipDataReady : OUT  std_logic;
         ethTxDataIn : OUT  std_logic_vector(7 downto 0);
         ethTxDataValid : OUT  std_logic;
         ethTxDataLastByte : OUT  std_logic;
         ethTxDataReady : IN  std_logic
        );
    END COMPONENT;
    

   --Inputs
   signal ethClk125    : std_logic := '0';
   signal ethClk125Rst : std_logic := '0';
   signal ethClk62    : std_logic := '0';
   signal ethClk62Rst : std_logic := '0';

	signal ethCoreMacAddr : MacAddrType := MAC_ADDR_DEFAULT_C;
   signal ethCoreIpAddr  : IpAddrType  := IP_ADDR_DEFAULT_C;
   signal ch2IpAddr      : IpAddrType  := IP_ADDR_DEFAULT_C;

   signal phyRxLaneIn    : EthRxPhyLaneInType;
   signal phyTxLaneOut   : EthTxPhyLaneOutType;

   signal dummyPhyRxLaneIn    : EthRxPhyLaneInType;
   signal dummyPhyTxLaneOut   : EthTxPhyLaneOutType;   
   
   signal ethRxLinkSync  : sl;
   signal ethAutoNegDone : sl;   
   
   -- User Data signals
   signal tpData      : slv(31 downto 0);
   signal tpDataValid : sl;
   signal tpDataLast  : sl := '0';
   signal tpDataReady : sl;

   signal tpData1      : slv(31 downto 0);
   signal tpDataValid1 : sl;
   signal tpDataLast1  : sl := '0';
   signal tpDataReady1 : sl;
   
   -- Clock period definitions
   constant ethClk125_period : time :=  8 ns;
   constant ethClk62_period  : time := 16 ns;

   constant GATE_DELAY_C  : time := 1 ns;
   
BEGIN

   ch2IpAddr(0) <= x"15";

   --------------------------------
   -- Gigabit Ethernet Interface --
   --------------------------------
   U_Eth1000BaseXCore : entity work.Eth1000BaseXCore
      generic map (
         NUM_IP_G      => 2,
         EN_AUTONEG_G  => true,
         SIM_SPEEDUP_G => true,
         GATE_DELAY_G  => GATE_DELAY_C
      )
      port map ( 
         -- 125 MHz clock and reset
         eth125Clk          => ethClk125,
         eth125Rst          => ethClk125Rst,
         -- 62 MHz clock and reset
         eth62Clk           => ethClk62,
         eth62Rst           => ethClk62Rst,
         -- Addressing
         macAddr            => ethCoreMacAddr,
         ipAddrs            => (0 => ethCoreIpAddr, 1 => ch2IpAddr),
         udpPorts           => (0 => x"07D0", 1 => x"07D1"), --x7D0 = 2000
         -- Data to/from GT
         phyRxData          => phyRxLaneIn,
         phyTxData          => phyTxLaneOut,
         -- Status signals
         statusSync         => ethRxLinkSync,
         statusAutoNeg      => ethAutoNegDone,
         -- User clock and reset
         userClk            => ethClk125,
         userRst            => ethClk125Rst,
         -- User data
         userTxData         => (0 => tpData, 1 => tpData1),
         userTxDataValid    => (0 => tpDataValid, 1 => tpDataValid1),
         userTxDataLast     => (0 => tpDataLast, 1 => tpDataLast1),
         userTxDataReady(1) => tpDataReady1,
         userTxDataReady(0) => tpDataReady,
         userRxData         => open,
         userRxDataValid    => open,
         userRxDataLast     => open,
         userRxDataReady    => (others => '1')
      );

   U_TpGenTx : entity work.TpGenTx
      generic map (
         NUM_WORDS_G   => 1000,
         WAIT_CYCLES_G => 100,
         GATE_DELAY_G  => GATE_DELAY_C
      )
      port map (
         -- User clock and reset
         userClk         => ethClk125,
         userRst         => ethClk125Rst or not(ethAutoNegDone),
         -- Connection to user logic
         userTxData      => tpData,
         userTxDataValid => tpDataValid,
         userTxDataLast  => tpDataLast,
         userTxDataReady => tpDataReady
      );

   U_TpGenTx1 : entity work.TpGenTx
      generic map (
         NUM_WORDS_G   => 100,
         WAIT_CYCLES_G => 2500,
         GATE_DELAY_G  => GATE_DELAY_C
      )
      port map (
         -- User clock and reset
         userClk         => ethClk125,
         userRst         => ethClk125Rst or not(ethAutoNegDone),
         -- Connection to user logic
         userTxData      => tpData1,
         userTxDataValid => tpDataValid1,
         userTxDataLast  => tpDataLast1,
         userTxDataReady => tpDataReady1
      );      
      
   --------------------------------
   -- DummyCore Ethernet Interface --
   --------------------------------
   U_DummyCore : entity work.Eth1000BaseXCore
      generic map (
         NUM_IP_G      => 1,
         EN_AUTONEG_G  => true,
         SIM_SPEEDUP_G => true,
         GATE_DELAY_G  => GATE_DELAY_C
      )
      port map ( 
         -- 125 MHz clock and reset
         eth125Clk          => ethClk125,
         eth125Rst          => ethClk125Rst,
         -- 62 MHz clock and reset
         eth62Clk           => ethClk62,
         eth62Rst           => ethClk62Rst,
         -- Addressing
         macAddr            => ethCoreMacAddr,
         ipAddrs            => (0 => ethCoreIpAddr),
         udpPorts           => (0 => x"07D0"), --x7D0 = 2000
         -- Data to/from GT
         phyRxData          => dummyPhyRxLaneIn,
         phyTxData          => dummyPhyTxLaneOut,
         -- Status signals
         statusSync         => ethRxLinkSync,
         statusAutoNeg      => ethAutoNegDone,
         -- User clock and reset
         userClk            => ethClk125,
         userRst            => ethClk125Rst,
         -- User data
         userTxData         => (0 => tpData),
         userTxDataValid    => (0 => tpDataValid),
         userTxDataLast     => (0 => tpDataLast),
         userTxDataReady(0) => tpDataReady,
         userRxData         => open,
         userRxDataValid    => open,
         userRxDataLast     => open,
         userRxDataReady    => (others => '1')
      );

      
   -- Match up B TX to A RX
   phyRxLaneIn.data    <= dummyPhyTxLaneOut.data;
   phyRxLaneIn.dataK   <= dummyPhyTxLaneOut.dataK;
   phyRxLaneIn.dispErr <= (others => '0');
   phyRxLaneIn.decErr  <= (others => '0');
   -- Match up A TX to B RX
   dummyPhyRxLaneIn.data    <= phyTxLaneOut.data;
   dummyPhyRxLaneIn.dataK   <= phyTxLaneOut.dataK;
   dummyPhyRxLaneIn.dispErr <= (others => '0');
   dummyPhyRxLaneIn.decErr  <= (others => '0');      
      
   -- Clock process definitions
   ethClk125_process : process
   begin
		ethClk125 <= '0';
		wait for ethClk125_period/2;
		ethClk125 <= '1';
		wait for ethClk125_period/2;
   end process;
   ethClk62_process : process
   begin
		ethClk62 <= '0';
		wait for ethClk62_period/2;
		ethClk62 <= '1';
		wait for ethClk62_period/2;
   end process;
   

   -- Stimulus process
   stim_proc: process
   begin		
      -- hold reset state for 100 ns.
      ethClk125Rst <= '1';
      ethClk62Rst  <= '1';
      wait for 100 ns;
      ethClk125Rst <= '0';
      ethClk62Rst  <= '0';
      wait for ethClk125_period*10;

      -- insert stimulus here 

      wait;
   end process;

END;
