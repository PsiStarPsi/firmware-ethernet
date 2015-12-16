-------------------------------------------------------------------------------
-- Title         : Ethernet Lane
-- Project       : General Purpose Core
-------------------------------------------------------------------------------
-- File          : EthTx.vhd
-- Author        : Kurtis Nishimura
-------------------------------------------------------------------------------
-- Description:
-- Ethernet interface TX
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
--use IEEE.NUMERIC_STD.ALL;
use work.UtilityPkg.all;
use work.Eth1000BaseXPkg.all;
use work.GigabitEthPkg.all;

entity EthTx is
   generic (
      GATE_DELAY_G : time := 1 ns
   );
   port ( 
      -- 125 MHz clock and reset
      ethClk           : in  sl;
      ethRst           : in  sl;
      -- Addressing
      macAddr          : in MacAddrType := MAC_ADDR_DEFAULT_C;
      -- Connection to GT
      macData          : out EthMacDataType;  
      -- Connection to upper level ARP 
      arpTxSenderMac   : in  MacAddrType;
      arpTxSenderIp    : in  IpAddrType;
      arpTxTargetMac   : in  MacAddrType;
      arpTxTargetIp    : in  IpAddrType;
      arpTxOp          : in  slv(15 downto 0);
      arpTxReq         : in  sl;
      arpTxAck         : out sl;
      -- Connection to IPv4 interface
      ipTxDestMac      : in  MacAddrType;
      ipTxData         : in  slv(7 downto 0);
      ipTxDataValid    : in  sl;
      ipTxDataLastByte : in  sl;
      ipTxDataReady    : out sl
   );
end EthTx;

architecture Behavioral of EthTx is

   -- Communication between MAC and Ethernet framer
   signal macTxData         : slv(7 downto 0);
   signal macTxDataValid    : sl;
   signal macTxDataLastByte : sl;
   signal macTxDataReady    : sl;
   -- Communication between Ethernet framer and higher level protocols
   signal ethTxEtherType    : EtherType;
   signal ethTxData         : slv(7 downto 0);
   signal ethTxDataValid    : sl;
   signal ethTxDataLastByte : sl;
   signal ethTxDataReady    : sl;
   -- Local connection to ARP interface
   signal arpTxData          : slv(7 downto 0);
   signal arpTxDataValid     : sl;
   signal arpTxDataLastByte  : sl;
   signal arpTxDataReady     : sl;
   signal iArpTxAck          : sl;   
   --
   signal ethTxDestMac : MacAddrType;

begin

   -- Transmit data from Tx
   U_MacTx : entity work.Eth1000BaseXMacTx
      generic map (
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map (
         -- 125 MHz ethernet clock in
         ethTxClk         => ethClk, 
         ethTxRst         => ethRst,
         -- User data to be sent
         userDataIn       => macTxData,
         userDataValid    => macTxDataValid,
         userDataLastByte => macTxDataLastByte,
         userDataReady    => macTxDataReady,
         -- Data out to the GT
         macDataOut       => macData
      );

   -- Ethernet Type II Frame Transmitter
   U_EthFrameTx : entity work.EthFrameTx 
      generic map (
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map ( 
         -- 125 MHz ethernet clock in
         ethTxClk          => ethClk,
         ethTxRst          => ethRst,
         -- Data for the header
         ethTxDestMac      => ethTxDestMac,
         ethTxSrcMac       => macAddr,
         ethTxEtherType    => ethTxEtherType,
         -- User data to be sent
         ethTxDataIn       => ethTxData,
         ethTxDataValid    => ethTxDataValid,
         ethTxDataLastByte => ethTxDataLastByte,
         ethTxDataReady    => ethTxDataReady,
         -- Data output
         macTxDataOut      => macTxData,
         macTxDataValid    => macTxDataValid,
         macTxDataLastByte => macTxDataLastByte,
         macTxDataReady    => macTxDataReady
      ); 

   -- ARP Packet Transmitter
   U_ArpPacketTx : entity work.ArpPacketTx
      generic map (
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map ( 
         -- 125 MHz ethernet clock in
         ethTxClk          => ethClk,
         ethTxRst          => ethRst,
         -- Data to send
         arpSenderMac      => arpTxSenderMac,
         arpSenderIp       => arpTxSenderIp,
         arpTargetMac      => arpTxTargetMac,
         arpTargetIp       => arpTxTargetIp,
         arpOp             => arpTxOp,
         arpReq            => arpTxReq,
         arpAck            => iArpTxAck,
         -- User data to be sent
         ethTxData         => arpTxData,
         ethTxDataValid    => arpTxDataValid,
         ethTxDataLastByte => arpTxDataLastByte,
         ethTxDataReady    => arpTxDataReady
      );

   -- Arbiter to MUX between ARP requests and IP data
   U_ArpIpArbiter : entity work.ArpIpArbiter
      generic map (
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map (
         -- 125 MHz ethernet clock in
         ethTxClk          => ethClk,
         ethTxRst          => ethRst,
         -- ARP request/ack, data interface
         arpTxReq          => arpTxReq,
         arpTxAck          => iArpTxAck,
         arpTxData         => arpTxData,
         arpTxDataValid    => arpTxDataValid,
         arpTxDataLastByte => arpTxDataLastByte,
         arpTxDataReady    => arpTxDataReady,
         -- IPv4 data interface
         ipTxData          => ipTxData,
         ipTxDataValid     => ipTxDataValid,
         ipTxDataLastByte  => ipTxDataLastByte,
         ipTxDataReady     => ipTxDataReady,
         -- Output MUXed data
         ethTxEtherType    => ethTxEtherType,
         ethTxData         => ethTxData,
         ethTxDataValid    => ethTxDataValid,
         ethTxDataLastByte => ethTxDataLastByte,
         ethTxDataReady    => ethTxDataReady
      );      
   arpTxAck <= iArpTxAck;
   
   process(ethClk) begin
      if rising_edge(ethClk) then
         if ethRst = '1' then
            ethTxDestMac <= MAC_ADDR_INIT_C;
         elsif arpTxDataValid = '1' then
            ethTxDestMac <= arpTxTargetMac;
         elsif ipTxDestMac /= MAC_ADDR_INIT_C then
            ethTxDestMac <= ipTxDestMac;
         end if;
      end if;
   end process;
      
end Behavioral;

