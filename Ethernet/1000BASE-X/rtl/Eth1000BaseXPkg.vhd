-------------------------------------------------------------------------------
-- Title         : Gigabit Ethernet Package
-- Project       : General Purpose Core
-------------------------------------------------------------------------------
-- File          : Eth1000BaseXPkg.vhd
-- Author        : Kurtis Nishimura
-------------------------------------------------------------------------------
-- Description:
-- Gigabit ethernet constants & types.
-------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
use work.UtilityPkg.all;

package Eth1000BaseXPkg is

   -----------------------------------------------------
   -- Constants
   -----------------------------------------------------
  
   -- 8B10B Characters
   constant K_COM_C  : slv(7 downto 0) := "10111100"; -- K28.5, 0xBC
   constant D_215_C  : slv(7 downto 0) := "10110101"; -- D21.5, 0xB5
   constant D_022_C  : slv(7 downto 0) := "01000010"; -- D2.2,  0x42
   constant D_056_C  : slv(7 downto 0) := "11000101"; -- D5.6,  0xC5
   constant D_162_C  : slv(7 downto 0) := "01010000"; -- D16.2, 0x50
   
   -- Ordered sets
   constant OS_C1_C  : slv(15 downto 0) := D_215_C & K_COM_C; -- /C1/ 0xB5BC
   constant OS_C2_C  : slv(15 downto 0) := D_022_C & K_COM_C; -- /C2/ 0x42BC
   constant OS_I1_C  : slv(15 downto 0) := D_056_C & K_COM_C; -- /I1/ 0xC5BC
   constant OS_I2_C  : slv(15 downto 0) := D_162_C & K_COM_C; -- /I2/ 0x50BC
   constant K_SOP_C  : slv( 7 downto 0) := "11111011";        -- K27.7, 0xFB /S/ Start of packet
   constant K_EOP_C  : slv( 7 downto 0) := "11111101";        -- K29.7, 0xFD /T/ End of packet
   constant K_CAR_C  : slv( 7 downto 0) := "11110111";        -- K23.7, 0xF7 /R/ Carrier extend
   constant K_ERR_C  : slv( 7 downto 0) := "11111110";        -- K30.7, 0xFE /V/ Error propagation
   constant OS_BL_C  : slv(15 downto 0) := (others => '0');   -- Breaklink 0x0000
   
   -- Configuration registers
   -- No pause frames supported
   constant OS_CN_C  : slv(15 downto 0) := x"0020"; -- Configuration reg, ack bit unset
   constant OS_CA_C  : slv(15 downto 0) := x"4020"; -- Configuration reg, ack bit set
   -- Pause frames supported (this version of autonegotiation is not implemented yet)
   -- constant OS_CN_C  : slv(15 downto 0) := x"01a0";           --Config reg, no ack
   -- constant OS_CA_C  : slv(15 downto 0) := x"41a0";           --Config reg, with ack
      
   -- Link timer, assuming 62.5 MHz (spec is 10 ms [+ 10 ms - 0 ms])
   constant LINK_TIMER_C : natural := 937500; -- 937500 (0xE4E1C) cycles @ 62.5 MHz, ~15 ms 
   
   type EthRxPhyLaneInType is record
      data    : slv(15 downto 0); -- PHY receive data
      dataK   : slv( 1 downto 0); -- PHY receive data is K character
      dispErr : slv( 1 downto 0); -- PHY receive data has disparity error
      decErr  : slv( 1 downto 0); -- PHY receive data not in table
   end record EthRxPhyLaneInType;
   constant ETH_RX_PHY_LANE_IN_INIT_C : EthRxPhyLaneInType := (
      data    => (others => '0'),
      dataK   => (others => '0'),
      dispErr => (others => '0'),
      decErr  => (others => '0')
   );
   type EthRxPhyLaneInArray is array (natural range <>) of EthRxPhyLaneInType;
   
   type EthTxPhyLaneOutType is record
      data  : slv(15 downto 0); -- PHY transmit data
      dataK : slv(1 downto 0);  -- PHY transmit data is K character
      valid : sl;
   end record EthTxPhyLaneOutType;
   constant ETH_TX_PHY_LANE_OUT_INIT_C : EthTxPhyLaneOutType := (
      data  => (others => '0'),
      dataK => (others => '0'),
      valid => '0'
   );
   type EthTxPhyLaneOutArray is array (natural range <>) of EthTxPhyLaneOutType;
   
end Eth1000BaseXPkg;

package body Eth1000BaseXPkg is
      
end package body Eth1000BaseXPkg;
