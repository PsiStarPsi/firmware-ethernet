----------------------------------------------------------------------------------
-- Company: 
-- Engineer:  
-- 
-- Create Date:    13:21:31 07/23/2015 
-- Design Name: 
-- Module Name:    scrodEthernetExample - Behavioral 
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

entity scrodEthernetExample is
   generic (
      REG_ADDR_BITS_G : integer := 16;
      REG_DATA_BITS_G : integer := 16;
      NUM_IP_G        : integer := 2;
      GATE_DELAY_G    : time := 1 ns
   );
   port ( 
      -- Direct GT connections
      gtTxP        : out sl;
      gtTxN        : out sl;
      gtRxP        :  in sl;
      gtRxN        :  in sl;
      gtClkP       :  in sl;
      gtClkN       :  in sl;
      -- Alternative clock input
		fabClkP      :  in sl;
		fabClkN      :  in sl;
      -- SFP transceiver disable pin
      txDisable    : out sl;
      -- Status and diagnostics out
      ethSync      : out  sl;
      ethReady     : out  sl;
      led          : out  slv(15 downto 0)
   );
end scrodEthernetExample;

architecture Behavioral of scrodEthernetExample is

   signal fabClk       : sl;
   signal ethClk62     : sl;
   signal ethClk125    : sl;

   signal userRst     : sl;

   signal ethRxLinkSync  : sl;
   signal ethAutoNegDone : sl;

	signal ethCoreMacAddr : MacAddrType := MAC_ADDR_DEFAULT_C;
   signal ethCoreIpAddr  : IpAddrType  := IP_ADDR_DEFAULT_C;
   signal ethCoreIpAddr1 : IpAddrType  := (3 => x"C0", 2 => x"A8", 1 => x"01", 0 => x"21");
   
   signal tpData      : slv(31 downto 0);
   signal tpDataValid : sl;
   signal tpDataLast  : sl;
   signal tpDataReady : sl;
   
   -- User Data interfaces
   signal userTxDataChannels : Word32Array(NUM_IP_G-1 downto 0);
   signal userTxDataValids   : slv(NUM_IP_G-1 downto 0);
   signal userTxDataLasts    : slv(NUM_IP_G-1 downto 0);
   signal userTxDataReadys   : slv(NUM_IP_G-1 downto 0);
   signal userRxDataChannels : Word32Array(NUM_IP_G-1 downto 0);
   signal userRxDataValids   : slv(NUM_IP_G-1 downto 0);
   signal userRxDataLasts    : slv(NUM_IP_G-1 downto 0);
   signal userRxDataReadys   : slv(NUM_IP_G-1 downto 0);

   -- Register control interfaces
   signal regAddr     : slv(REG_ADDR_BITS_G-1 downto 0);
   signal regWrData   : slv(REG_DATA_BITS_G-1 downto 0);
   signal regRdData   : slv(REG_DATA_BITS_G-1 downto 0);
   signal regReq      : sl;
   signal regOp       : sl;
   signal regAck      : sl;
   
   -- Test registers
   -- Default is to send 1000 counter words once per second.
   signal waitCyclesHigh : slv(15 downto 0) := x"0773";
   signal waitCyclesLow  : slv(15 downto 0) := x"5940";
   signal numWords       : slv(15 downto 0) := x"03E8";
   
begin

   ethSync           <= ethRxLinkSync;
   ethReady          <= ethAutoNegDone;

   U_IBUFGDS : IBUFGDS port map ( I => fabClkP, IB => fabClkN, O => fabClk);

   --------------------------------
   -- Gigabit Ethernet Interface --
   --------------------------------
   U_S6EthTop : entity work.S6EthTop
      generic map (
         NUM_IP_G     => 2
      )
      port map (
         -- Direct GT connections
         gtTxP           => gtTxP,
         gtTxN           => gtTxN,
         gtRxP           => gtRxP,
         gtRxN           => gtRxN,
         gtClkP          => gtClkP,
         gtClkN          => gtClkN,
         -- Alternative clock input from fabric
         fabClkIn        => fabClk,
         -- SFP transceiver disable pin
         txDisable       => txDisable,
         -- Clocks out from Ethernet core
         ethUsrClk62     => ethClk62,
         ethUsrClk125    => ethClk125,
         -- Status and diagnostics out
         ethSync         => ethRxLinkSync,
         ethReady        => ethAutoNegDone,
         led             => led,
         -- Core settings in 
         macAddr         => ethCoreMacAddr,
         ipAddrs         => (0 => ethCoreIpAddr, 1 => ethCoreIpAddr1),
         udpPorts        => (0 => x"07D0",       1 => x"07D1"), --x7D0 = 2000,
         -- User clock inputs
         userClk         => ethClk125,
         userRstIn       => '0',
         userRstOut      => userRst,
         -- User data interfaces
         userTxData      => userTxDataChannels,
         userTxDataValid => userTxDataValids,
         userTxDataLast  => userTxDataLasts,
         userTxDataReady => userTxDataReadys,
         userRxData      => userRxDataChannels,
         userRxDataValid => userRxDataValids,
         userRxDataLast  => userRxDataLasts,
         userRxDataReady => userRxDataReadys
      );

   U_TpGenTx : entity work.TpGenTx
      generic map (
--         NUM_WORDS_G   => 1000,
--         WAIT_CYCLES_G => 100,
         GATE_DELAY_G  => GATE_DELAY_G
      )
      port map (
         -- User clock and reset
         userClk         => ethClk125,
         userRst         => userRst,
         -- Configuration
         waitCycles      => waitCyclesHigh & waitCyclesLow,
         numWords        => x"0000" & numWords,
         -- Connection to user logic
         userTxData      => tpData,
         userTxDataValid => tpDataValid,
         userTxDataLast  => tpDataLast,
         userTxDataReady => tpDataReady
      );

   -- Channel 0 TX high speed test pattern
   --           RX unused
   userTxDataChannels(0) <= tpData;
   userTxDataValids(0)   <= tpDataValid;
   userTxDataLasts(0)    <= tpDataLast;
   tpDataReady           <= userTxDataReadys(0);
   -- Note that the Channel 0 RX channels are unused here
   --userRxDataChannels;
   --userRxDataValids;
   --userRxDataLasts;
   userRxDataReadys(0) <= '1';

   -- Channel 1 can be modified to a a simple loopback like this:
   -- userTxDataChannels(1) <= userRxDataChannels(1);
   -- userTxDataValids(1)   <= userRxDataValids(1);
   -- userTxDataLasts(1)    <= userRxDataLasts(1);
   -- userRxDataReadys(1)   <= userTxDataReadys(1);      
   -- ...
   -- Instead of this:
   -- Channel 1 as a command interpreter
   U_CommandInterpreter : entity work.CommandInterpreter
      generic map (
         REG_ADDR_BITS_G => 16,
         REG_DATA_BITS_G => 16,
         GATE_DELAY_G    => GATE_DELAY_G
      )
      port map ( 
         -- User clock and reset
         usrClk      => ethClk125,
         usrRst      => userRst,
         -- Incoming data
         rxData      => userRxDataChannels(1),
         rxDataValid => userRxDataValids(1),
         rxDataLast  => userRxDataLasts(1),
         rxDataReady => userRxDataReadys(1),
         -- Outgoing response
         txData      => userTxDataChannels(1),
         txDataValid => userTxDataValids(1),
         txDataLast  => userTxDataLasts(1),
         txDataReady => userTxDataReadys(1),
         -- This board ID
         myId        => x"00AB",
         -- Register interfaces
         regAddr     => regAddr,
         regWrData   => regWrData,
         regRdData   => regRdData,
         regReq      => regReq,
         regOp       => regOp,
         regAck      => regAck
      );

   -- A few registers to toy with
   process(ethClk125) begin
      if rising_edge(ethClk125) then
         if userRst = '1' then
            regAck    <= '0';
            regRdData <= (others => '0');
         elsif regReq = '1' then
            regAck <= regReq;
            case regAddr is
               when x"0000" => regRdData <= numWords;
                               if regOp = '1' then
                                  numWords <= regWrData;
                               end if;
               when x"0001" => regRdData <= waitCyclesHigh;
                               if regOp = '1' then
                                  waitCyclesHigh <= regWrData;
                               end if;
               when x"0002" => regRdData <= waitCyclesLow;
                               if regOp = '1' then
                                  waitCyclesLow <= regWrData;
                               end if;                               
               when others  =>
                  regRdData <= (others => '0');
            end case;
         else
            regAck <= '0';
         end if;
      end if;
   end process;
         
end Behavioral;

