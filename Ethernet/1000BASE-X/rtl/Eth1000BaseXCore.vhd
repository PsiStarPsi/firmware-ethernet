-------------------------------------------------------------------------------
-- Title         : Ethernet Interface
-- Project       : General Purpose Core
-------------------------------------------------------------------------------
-- File          : Eth1000BaseXCore.vhd
-- Author        : Kurtis Nishimura
-------------------------------------------------------------------------------
-- Description:
-- Ethernet interface 
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
--use IEEE.NUMERIC_STD.ALL;
use work.UtilityPkg.all;
use work.Eth1000BaseXPkg.all;
use work.GigabitEthPkg.all;

entity Eth1000BaseXCore is
   generic (
      NUM_IP_G        : integer := 1;
      MTU_SIZE_G      : integer := 1500;
      LITTLE_ENDIAN_G : boolean := true;
      EN_AUTONEG_G    : boolean := true;
      SIM_SPEEDUP_G   : boolean := false;
      GATE_DELAY_G    : time := 1 ns
   );
   port ( 
      -- 125 MHz clock and reset
      eth125Clk       : in  sl;
      eth125Rst       : in  sl;
      -- 62 MHz clock and reset
      eth62Clk        : in  sl;
      eth62Rst        : in  sl;
      -- Addressing
      macAddr         : in  MacAddrType := MAC_ADDR_DEFAULT_C;
      ipAddrs         : in  IpAddrArray(NUM_IP_G-1 downto 0) := (others => IP_ADDR_DEFAULT_C);
      udpPorts        : in  Word16Array(NUM_IP_G-1 downto 0) := (others => (others => '0'));
      -- Data to/from GT
      phyRxData       : in  EthRxPhyLaneInType;
      phyTxData       : out EthTxPhyLaneOutType;
      -- Status signals
      statusSync      : out sl;
      statusAutoNeg   : out sl;
      statusArpDone   : out slv(NUM_IP_G-1 downto 0);
      -- User clock and reset
      userClk         : in  sl;
      userRst         : in  sl;
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
end Eth1000BaseXCore;

architecture Behavioral of Eth1000BaseXCore is   

   signal macTxData : EthMacDataType;
   signal macRxData : EthMacDataType;   

   signal anPhyTxData  : EthTxPhyLaneOutType;  
   signal ethPhyTxData : EthTxPhyLaneOutType;

   signal autonegDone : sl;
   signal linkSynced  : sl;

begin

   statusSync    <= linkSynced;
   statusAutoNeg <= autonegDone when EN_AUTONEG_G = true else '1';

   -----------------------------
   -- Core Ethernet Interface --
   -----------------------------
   U_EthCore : entity work.EthCore 
      generic map (
         NUM_IP_G        => NUM_IP_G,
         MTU_SIZE_G      => MTU_SIZE_G,
         LITTLE_ENDIAN_G => LITTLE_ENDIAN_G,
         GATE_DELAY_G    => GATE_DELAY_G
      )
      port map ( 
         -- 125 MHz clock and reset
         ethClk          => eth125Clk,
         ethRst          => eth125Rst,
         -- Addressing
         macAddr         => macAddr,
         ipAddrs         => ipAddrs,
         udpPorts        => udpPorts,
         -- Connection to physical interface (GT or otherwise)
         macTxData       => macTxData,
         macRxData       => macRxData,
         -- User clock and reset
         userClk         => userClk,
         userRst         => userRst,
         -- Connection to user logic
         userTxData      => userTxData,
         userTxDataValid => userTxDataValid,
         userTxDataLast  => userTxDataLast,
         userTxDataReady => userTxDataReady,
         userRxData      => userRxData,
         userRxDataValid => userRxDataValid,
         userRxDataLast  => userRxDataLast,
         userRxDataReady => userRxDataReady
      );

   -----------------------------
   -- Width translation       --
   -----------------------------
   -- TX data width translation
   U_Mux8to16 : entity work.Eth1000BaseX8To16Mux
      generic map (
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map (
         -- Clocking to deal with the GT data out (62.5 MHz)
         eth62Clk      => eth62Clk,
         eth62Rst      => eth62Rst,
         -- 125 MHz clock for 8 bit inputs
         eth125Clk     => eth125Clk,
         eth125Rst     => eth125Rst,
         -- PHY (16 bit) data interface out
         ethPhyDataOut => ethPhyTxData,
         -- MAC (8 bit) data interface out
         ethMacDataIn  => macTxData
      );
   -- RX data width translation
   U_Mux16to8 : entity work.Eth1000BaseX16To8Mux
      generic map (
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map (
         -- Clocking to deal with the GT data out (62.5 MHz)
         eth62Clk      => eth62Clk,
         eth62Rst      => eth62Rst,
         -- 125 MHz clock for 8 bit inputs
         eth125Clk     => eth125Clk,
         eth125Rst     => eth125Rst,
         -- PHY (16 bit) data interface
         ethPhyDataIn  => phyRxData,
         -- MAC (8 bit) data interface
         ethMacDataOut => macRxData
      );      

   --------------------------
   -- Link synchronization --
   --------------------------
   U_LinkSync : entity work.Eth1000BaseXRxSync
      generic map (
         GATE_DELAY_G  => GATE_DELAY_G,
         PIPE_STAGES_G => 2
      )
      port map ( 
         -- GT user clock and reset (62.5 MHz)
         ethRx62Clk  => eth62Clk,
         ethRx62Rst  => eth62Rst,
         -- Local side has synchronization
         rxLinkSync  => linkSynced,
         -- Incoming data from GT
         phyRxData   => phyRxData
      ); 
      
   ---------------------
   -- Autonegotiation --
   ---------------------
   U_AutoNeg : entity work.Eth1000BaseXAutoNeg
      generic map (
         GATE_DELAY_G  => GATE_DELAY_G,
         PIPE_STAGES_G => 2,
         SIM_SPEEDUP_G => SIM_SPEEDUP_G
      )
      port map ( 
         -- GT user clock and reset (62.5 MHz)
         ethRx62Clk  => eth62Clk,
         ethRx62Rst  => eth62Rst,
         -- Autonegotiation is done
         autonegDone => autonegDone,
         -- Link is synchronized
         rxLinkSync  => linkSynced,
         -- Physical Interface Signals
         phyRxData   => phyRxData,
         phyTxData   => anPhyTxData
      );

   ----------------------------------------------------------------
   -- Multiplex data source between autonegotiation and MAC data --
   ----------------------------------------------------------------
   process(eth62Clk)
   begin
      if rising_edge(eth62Clk) then
         if (autonegDone = '1' and ethPhyTxData.valid = '1') or (EN_AUTONEG_G = false) then
            phyTxData <= ethPhyTxData after GATE_DELAY_G;
         else
            phyTxData <= anPhyTxData after GATE_DELAY_G;
         end if;
      end if;
   end process;
      
end Behavioral;

