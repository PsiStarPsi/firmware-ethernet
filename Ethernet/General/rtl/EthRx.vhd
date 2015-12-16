-------------------------------------------------------------------------------
-- Title         : Ethernet Lane
-- Project       : General Purpose Core
-------------------------------------------------------------------------------
-- File          : EthRx.vhd
-- Author        : Kurtis Nishimura
-------------------------------------------------------------------------------
-- Description:
-- Ethernet interface RX
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
--use IEEE.NUMERIC_STD.ALL;
use work.UtilityPkg.all;
use work.Eth1000BaseXPkg.all;
use work.GigabitEthPkg.all;

entity EthRx is
   generic (
      GATE_DELAY_G : time := 1 ns
   );
   port ( 
      -- 125 MHz clock and reset
      ethClk            : in  sl;
      ethRst            : in  sl;
      -- Addressing
      macAddr           : in MacAddrType := MAC_ADDR_DEFAULT_C;
      -- Connection to GT
      macData           : in EthMacDataType;
      -- Connection to upper level ARP
      arpRxOp           : out slv(15 downto 0);
      arpRxSenderMac    : out MacAddrType;
      arpRxSenderIp     : out IpAddrType;
      arpRxTargetMac    : out MacAddrType;
      arpRxTargetIp     : out IpAddrType;
      arpRxValid        : out sl;
      -- Connection to upper level IP interface
      ethRxData         : out slv(7 downto 0);
      ethRxSenderMac    : out MacAddrType;
      ethRxDataValid    : out sl;
      ethRxDataLastByte : out sl
   );
end EthRx;

architecture Behavioral of EthRx is

   -- Communication between MAC and Ethernet framer
   signal macRxData      : slv(7 downto 0) := (others => '0');
   signal macRxDataValid : sl := '0';
   signal macRxDataLast  : sl := '0';
   signal macRxBadFrame  : sl := '0';
   -- Communication between Ethernet framer and higher level protocols
   signal ethRxEtherType    : EtherType   := ETH_TYPE_INIT_C;
   signal ethRxSrcMac       : MacAddrType := MAC_ADDR_INIT_C;
   signal ethRxDestMac      : MacAddrType := MAC_ADDR_INIT_C;
   signal rawEthRxData      : std_logic_vector(7 downto 0);
   signal rawEthRxDataValid : std_logic;
   signal rawEthRxDataLast  : std_logic;
   

begin

   -- Receive into the Rx
   U_MacRx : entity work.Eth1000BaseXMacRx
      generic map (
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map (
         -- 125 MHz ethernet clock in
         ethRxClk       => ethClk,
         ethRxRst       => ethRst,
         -- Incoming data from the 16-to-8 mux
         macDataIn      => macData,
         -- Outgoing bytes and flags to the applications
         macRxData      => macRxData,
         macRxDataValid => macRxDataValid,
         macRxDataLast  => macRxDataLast,
         macRxBadFrame  => macRxBadFrame,
         -- Monitoring flags
         macBadCrcCount => open
      );
   
	-- Ethernet Type II Frame Receiver
   U_EthFrameRx : entity work.EthFrameRx 
      generic map (
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map (
         -- 125 MHz ethernet clock in
         ethRxClk       => ethClk,
         ethRxRst       => ethRst,
         -- Settings from the upper level
         macAddress     => macAddr,
         -- Incoming data from the MAC layer
         macRxData      => macRxData,
         macRxDataValid => macRxDataValid,
         macRxDataLast  => macRxDataLast,
         -- Outgoing data to next layer
         macRxBadFrame  => macRxBadFrame,
         ethRxEtherType => ethRxEtherType,
         ethRxSrcMac    => ethRxSrcMac,
         ethRxDestMac   => ethRxDestMac,
         ethRxData      => rawEthRxData,
         ethRxDataValid => rawEthRxDataValid,
         ethRxDataLast  => rawEthRxDataLast
      );

	-- ARP Packet Receiver
   U_ArpPacketRx : entity work.ArpPacketRx 
      generic map (
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map (
         -- 125 MHz ethernet clock in
         ethRxClk       => ethClk,
         ethRxRst       => ethRst,
         -- Incoming data from Ethernet frame
         ethRxSrcMac    => ethRxSrcMac,
         ethRxDestMac   => ethRxDestMac,
         ethRxData      => rawEthRxData,
         ethRxDataValid => rawEthRxDataValid,
         ethRxDataLast  => rawEthRxDataLast,
         -- Received data from ARP packet
         arpOp          => arpRxOp,
         arpSenderMac   => arpRxSenderMac,
         arpSenderIp    => arpRxSenderIp,
         arpTargetMac   => arpRxTargetMac,
         arpTargetIp    => arpRxTargetIp, 
         arpValid       => arpRxValid
      );
      
   -- IPv4 data out
   ethRxData         <= rawEthRxData      when ethRxEtherType = ETH_TYPE_IPV4_C else (others => '0');
   ethRxDataValid    <= rawEthRxDataValid when ethRxEtherType = ETH_TYPE_IPV4_C else '0';
   ethRxDataLastByte <= rawEthRxDataLast  when ethRxEtherType = ETH_TYPE_IPV4_C else '0';
   ethRxSenderMac    <= ethRxSrcMac       when ethRxEtherType = ETH_TYPE_IPV4_C else MAC_ADDR_INIT_C;

end Behavioral;

