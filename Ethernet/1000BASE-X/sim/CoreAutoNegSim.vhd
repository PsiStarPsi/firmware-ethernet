--------------------------------------------------------------------------------
-- Company: 
-- Engineer:
--
-- Create Date:   00:50:52 08/18/2015
-- Design Name:   
-- Module Name:   C:/Users/Kurtis/Desktop/testBed/ethernet/CoreAutoNegSim.vhd
-- Project Name:  ethernet
-- Target Device:  
-- Tool versions:  
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: EthFrameRx
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
use work.Eth1000BaseXPkg.all;
use work.GigabitEthPkg.all;
 
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--USE ieee.numeric_std.ALL;
 
ENTITY CoreAutoNegSim IS
END CoreAutoNegSim;
 
ARCHITECTURE behavior OF CoreAutoNegSim IS     

   -- Clocking
   signal eth125Clk : std_logic := '0';
   signal eth125Rst : std_logic := '0';
   signal eth62Clk : std_logic := '0';
   signal eth62Rst : std_logic := '0';

   signal aMacAddr : MacAddrType := MAC_ADDR_DEFAULT_C;
   signal bMacAddr : MacAddrType := ( 5 => x"A1",
                                      4 => x"B2",
                                      3 => x"C3",
                                      2 => x"D4",
                                      1 => x"E5",
                                      0 => x"F6" );

   signal aIpAddr : IpAddrType := ( 3 => conv_std_logic_vector(192,8),
                                    2 => conv_std_logic_vector(168,8),
                                    1 => conv_std_logic_vector(1,8),
                                    0 => conv_std_logic_vector(2,8) );
   signal bIpAddr : IpAddrType := IP_ADDR_DEFAULT_C;
   
   signal aRxData : EthRxPhyLaneInType;
   signal aTxData : EthTxPhyLaneOutType;

   signal bRxData : EthRxPhyLaneInType;
   signal bTxData : EthTxPhyLaneOutType;
   
   signal aSync   : sl;
   signal aAnDone : sl;
   signal bSync   : sl;
   signal bAnDone : sl;
   
   -- Clock period definitions
   constant ethClk_period : time := 8 ns;
   constant GATE_DELAY_C  : time := 1 ns;
   
BEGIN

   -- Match up B TX to A RX
   aRxData.data    <= bTxData.data;
   aRxData.dataK   <= bTxData.dataK;
   aRxData.dispErr <= (others => '0');
   aRxData.decErr  <= (others => '0');
   -- Match up A TX to B RX
   bRxData.data    <= aTxData.data;
   bRxData.dataK   <= aTxData.dataK;
   bRxData.dispErr <= (others => '0');
   bRxData.decErr  <= (others => '0');

   
   -- Core A
   U_CoreA : entity work.Eth1000BaseXCore
      generic map (
         NUM_IP_G      => 1,
         EN_AUTONEG_G  => true,
         SIM_SPEEDUP_G => true,
         GATE_DELAY_G  => GATE_DELAY_C
      )
      port map ( 
         -- 125 MHz clock and reset
         eth125Clk     => eth125Clk,
         eth125Rst     => eth125Rst,
         -- 62 MHz clock and reset
         eth62Clk      => eth62Clk,
         eth62Rst      => eth62Rst,
         -- User clock and reset
         userClk       => eth125Clk,
         userRst       => eth125Rst,
         -- Addressing
         macAddr       => aMacAddr,
         ipAddrs       => (0 => aIpAddr),
         -- Data to/from GT
         phyRxData     => aRxData,
         phyTxData     => aTxData,
         -- Status signals
         statusSync    => aSync,
         statusAutoNeg => aAnDone
      );

   -- Core B
   U_CoreB : entity work.Eth1000BaseXCore
      generic map (
         NUM_IP_G      => 1,
         EN_AUTONEG_G  => true,
         SIM_SPEEDUP_G => true,
         GATE_DELAY_G  => GATE_DELAY_C
      )
      port map ( 
         -- 125 MHz clock and reset
         eth125Clk     => eth125Clk,
         eth125Rst     => eth125Rst,
         -- 62 MHz clock and reset
         eth62Clk      => eth62Clk,
         eth62Rst      => eth62Rst,
         -- Addressing
         macAddr       => bMacAddr,
         ipAddrs       => (0 => bIpAddr),
         -- Data to/from GT
         phyRxData     => bRxData,
         phyTxData     => bTxData,
         -- Status signals
         statusSync    => bSync,
         statusAutoNeg => bAnDone
      );
      
   -- Clock process definitions
   ethRxClk_process :process
   begin
		eth125Clk <= '0';
		wait for ethClk_period/2;
		eth125Clk <= '1';
		wait for ethClk_period/2;
   end process;

   clk62_process : process(eth125Clk) begin
      if rising_edge(eth125Clk) then
         eth62Clk <= not(eth62Clk);
      end if;
   end process;
   
   -- Stimulus process
   stim_proc: process
   begin		

      eth125Rst <= '1';
      eth62Rst  <= '1';
      
      -- hold reset state for 100 ns.
      wait for 20 ns;	

      eth125Rst <= '0';
      eth62Rst <= '0';
      
      wait for ethClk_period*10;

      -- insert stimulus here 
      
      wait;
   end process;
   
END;
