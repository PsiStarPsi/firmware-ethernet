-------------------------------------------------------------------------------
-- Title         : Ethernet Interface
-- Project       : General Purpose Core
-------------------------------------------------------------------------------
-- File          : EthCore.vhd
-- Author        : Kurtis Nishimura
-------------------------------------------------------------------------------
-- Description:
-- Ethernet interface 
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.Eth1000BaseXPkg.all;
use work.GigabitEthPkg.all;

entity EthCore is
   generic (
      NUM_IP_G        : integer := 1;
      MTU_SIZE_G      : integer := 1500;
      LITTLE_ENDIAN_G : boolean := true;
      GATE_DELAY_G    : time := 1 ns
   );
   port ( 
      -- 125 MHz clock and reset
      ethClk          : in  sl;
      ethRst          : in  sl;
      -- Addressing
      macAddr         : in  MacAddrType := MAC_ADDR_DEFAULT_C;
      ipAddrs         : in  IpAddrArray(NUM_IP_G-1 downto 0) := (others => IP_ADDR_DEFAULT_C);
      udpPorts        : in  Word16Array(NUM_IP_G-1 downto 0) := (others => (others => '0'));
      -- Connection to physical interface (GT or otherwise)
      macTxData       : out EthMacDataType;
      macRxData       : in  EthMacDataType;
      -- User clock and reset
      userClk         : in  sl;
      userRst         : in  sl;
      -- Connection to user logic
      userTxData      : in  Word32Array(NUM_IP_G-1 downto 0);
      userTxDataValid : in  slv(NUM_IP_G-1 downto 0);
      userTxDataLast  : in  slv(NUM_IP_G-1 downto 0);
      userTxDataReady : out slv(NUM_IP_G-1 downto 0);
      userRxData      : out Word32Array(NUM_IP_G-1 downto 0);
      userRxDataValid : out slv(NUM_IP_G-1 downto 0);
      userRxDataLast  : out slv(NUM_IP_G-1 downto 0);
      userRxDataReady : in  slv(NUM_IP_G-1 downto 0)
   );
end EthCore;

architecture Behavioral of EthCore is   

   -- Signals for ARP interfacing
   signal arpTxSenderMac : MacAddrType;
   signal arpTxSenderIp  : IpAddrType;
   signal arpTxTargetMac : MacAddrType;
   signal arpTxTargetIp  : IpAddrType;
   signal arpTxOp        : slv(15 downto 0);
   signal arpTxReq       : sl;
   signal arpTxAck       : sl;
   signal arpRxOp        : slv(15 downto 0);
   signal arpRxSenderMac : MacAddrType;
   signal arpRxSenderIp  : IpAddrType;
   signal arpRxTargetMac : MacAddrType;
   signal arpRxTargetIp  : IpAddrType;
   signal arpRxValid     : sl;
   
   -- TX interfaces
   signal multIpTxData         : Word8Array(NUM_IP_G-1 downto 0);
   signal multIpTxDataValid    : slv(NUM_IP_G-1 downto 0);
   signal multIpTxDataLastByte : slv(NUM_IP_G-1 downto 0);
   signal multIpTxDataReady    : slv(NUM_IP_G-1 downto 0);
   
   signal ipTxData      : Word32Array(NUM_IP_G-1 downto 0);
   signal ipTxDataValid : slv(NUM_IP_G-1 downto 0);
   signal ipTxDataReady : slv(NUM_IP_G-1 downto 0);
   
   signal muxIpTxData         : slv(7 downto 0);
   signal muxIpTxDataValid    : sl;
   signal muxIpTxDataLastByte : sl;
   signal muxIpTxDataReady    : sl;
   
   signal ipPacketLength  : Word16Array(NUM_IP_G-1 downto 0);
   signal ipPacketId      : Word16Array(NUM_IP_G-1 downto 0);
   signal ipMoreFragments : slv(NUM_IP_G-1 downto 0);
   signal ipFragOffset    : Word13Array(NUM_IP_G-1 downto 0);
   signal ipProtocol      : Word8Array(NUM_IP_G-1 downto 0);
   signal ipSrcAddr       : IpAddrArray(NUM_IP_G-1 downto 0);
   signal ipDstAddr       : IpAddrArray(NUM_IP_G-1 downto 0);
   
   signal udpTxData      : Word32Array(NUM_IP_G-1 downto 0);
   signal udpTxDataValid : slv(NUM_IP_G-1 downto 0);
   signal udpTxDataReady : slv(NUM_IP_G-1 downto 0);
   signal udpTxLength    : Word16Array(NUM_IP_G-1 downto 0);
   signal udpTxReq       : slv(NUM_IP_G-1 downto 0);
   signal udpTxAck       : slv(NUM_IP_G-1 downto 0);

   -- RX interfaces
   signal ethRxData      : slv(7 downto 0);
   signal ethRxDataValid : sl;
   signal ethRxDataLast  : sl;

   signal ipRxLength        : slv(15 downto 0);
   signal ipRxId            : slv(15 downto 0);
   signal ipRxMoreFragments : sl;
   signal ipRxFragOffset    : slv(12 downto 0);
   signal ipRxTtl           : slv( 7 downto 0);
   signal ipRxProtocol      : slv( 7 downto 0);
   signal ipRxSrcAddr       : IpAddrType;
   signal ipRxDstAddr       : IpAddrType;
   signal ipRxData          : slv(31 downto 0);
   signal ipRxDataValid     : sl;
   signal ipRxDataLast      : sl;

   signal udpRxSrcPort  : Word16Array(NUM_IP_G-1 downto 0);
   signal udpRxDstPort  : Word16Array(NUM_IP_G-1 downto 0);
   signal udpRxLength   : Word16Array(NUM_IP_G-1 downto 0);
   signal udpRxChecksum : Word16Array(NUM_IP_G-1 downto 0);
   
   signal udpTxDstPort  : Word16Array(NUM_IP_G-1 downto 0);
   
   signal iUserRxDataValid : slv(NUM_IP_G-1 downto 0);
   
   -- For optional endian reversal operations
   signal userTxDataByteOrdered : Word32Array(NUM_IP_G-1 downto 0);
   signal userRxDataByteOrdered : Word32Array(NUM_IP_G-1 downto 0);
   
begin

   ---------------------------------------
   -- Communications to top level ports --
   ---------------------------------------
   G_ByteSwizzle : if LITTLE_ENDIAN_G = true generate
      G_Swizzle : for i in NUM_IP_G-1 downto 0 generate
         userTxDataByteOrdered(i) <= userTxData(i)(7 downto 0) & userTxData(i)(15 downto 8) & userTxData(i)(23 downto 16) & userTxData(i)(31 downto 24);
         userRxData(i) <= userRxDataByteOrdered(i)(7 downto 0) & userRxDataByteOrdered(i)(15 downto 8) & userRxDataByteOrdered(i)(23 downto 16) & userRxDataByteOrdered(i)(31 downto 24);
      end generate;
   end generate;
   G_NoByteSwizzle : if LITTLE_ENDIAN_G = false generate
      G_NoSwizzle : for i in NUM_IP_G-1 downto 0 generate
         userTxDataByteOrdered(i) <= userTxData(i);
         userRxData(i)            <= userRxDataByteOrdered(i);
      end generate;
   end generate;
   
   --------------------------
   -- Ethernet Frame TX/RX --
   --------------------------
   U_EthTx : entity work.EthTx
      generic map (
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map ( 
         -- 125 MHz clock and reset
         ethClk           => ethClk,
         ethRst           => ethRst,
         -- Addressing
         macAddr          => macAddr,
         -- Connection to GT
         macData          => macTxData,  
         -- Connection to upper level ARP 
         arpTxSenderMac   => arpTxSenderMac,
         arpTxSenderIp    => arpTxSenderIp,
         arpTxTargetMac   => arpTxTargetMac,
         arpTxTargetIp    => arpTxTargetIp,
         arpTxOp          => arpTxOp,
         arpTxReq         => arpTxReq,
         arpTxAck         => arpTxAck,
         -- Connection to IPv4 interface
         ipTxData         => muxIpTxData,
         ipTxDataValid    => muxIpTxDataValid,
         ipTxDataLastByte => muxIpTxDataLastByte,
         ipTxDataReady    => muxIpTxDataReady
      );

   U_EthRx : entity work.EthRx
      generic map (
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map ( 
         -- 125 MHz clock and reset
         ethClk            => ethClk,
         ethRst            => ethRst,
         -- Addressing
         macAddr           => macAddr,
         -- Connection to GT
         macData           => macRxData,
         -- Connection to upper level ARP
         arpRxOp           => arpRxOp,
         arpRxSenderMac    => arpRxSenderMac,
         arpRxSenderIp     => arpRxSenderIp,
         arpRxTargetMac    => arpRxTargetMac,
         arpRxTargetIp     => arpRxTargetIp,
         arpRxValid        => arpRxValid,
         -- Connection to upper level IP interface
         ethRxData         => ethRxData,
         ethRxDataValid    => ethRxDataValid,
         ethRxDataLastByte => ethRxDataLast
      );
      
   ----------------------------
   -- Higher level protocols --
   ----------------------------

   -- ARP : respond to ARP requests based on our IPs
   U_ArpResponder : entity work.ArpResponder 
      generic map (
         NUM_IP_G     => NUM_IP_G,
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map (
         -- 125 MHz ethernet clock in
         ethClk         => ethClk,
         ethRst         => ethRst,
         -- Local MAC/IP settings
         macAddress     => macAddr,
         ipAddresses    => ipAddrs,
         -- Connection to ARP RX
         arpRxOp        => arpRxOp,
         arpRxSenderMac => arpRxSenderMac,
         arpRxSenderIp  => arpRxSenderIp,
         arpRxTargetMac => arpRxTargetMac,
         arpRxTargetIp  => arpRxTargetIp,
         arpRxValid     => arpRxValid,
         -- Connection to ARP TX
         arpTxSenderMac => arpTxSenderMac,
         arpTxSenderIp  => arpTxSenderIp,
         arpTxTargetMac => arpTxTargetMac,
         arpTxTargetIp  => arpTxTargetIp,
         arpTxOp        => arpTxOp,
         arpTxReq       => arpTxReq,
         arpTxAck       => arpTxAck
      ); 


   -- IPv4 TX arbitration
   U_IPv4Arbiter : entity work.IpV4Arbiter
      generic map (
         GATE_DELAY_G => GATE_DELAY_G,
         NUM_IP_G     => NUM_IP_G
      )
      port map (
         -- 125 MHz ethernet clock in
         ethTxClk             => ethClk,
         ethTxRst             => ethRst,
         -- Multiple data inputs 
         multIpTxDataIn       => multIpTxData,
         multIpTxDataValid    => multIpTxDataValid,
         multIpTxDataLastByte => multIpTxDataLastByte,
         multIpTxDataReady    => multIpTxDataReady,
         -- MUXed data out
         ipTxData             => muxIpTxData,
         ipTxDataValid        => muxIpTxDataValid,
         ipTxDataLastByte     => muxIpTxDataLastByte,
         ipTxDataReady        => muxIpTxDataReady
      );
      
   -- TX modules for each IP address
   G_UdpTxInstance : for i in NUM_IP_G - 1 downto 0 generate
      -- IPv4 TX packet transmission
      U_IPv4Tx : entity work.IPv4Tx 
         generic map (
            GATE_DELAY_G => GATE_DELAY_G
         )
         port map ( 
            -- 125 MHz ethernet clock in
            ethTxClk          => ethClk,
            ethTxRst          => ethRst,
            -- Header data
            ipPacketLength    => ipPacketLength(i),
            ipPacketId        => ipPacketId(i),
            ipMoreFragments   => ipMoreFragments(i),
            ipFragOffset      => ipFragOffset(i),
            ipProtocol        => ipProtocol(i),
            ipSrcAddr         => ipAddrs(i),
            ipDstAddr         => arpTxTargetIp,
            -- User data to be sent
            ipData            => ipTxData(i),
            ipDataValid       => ipTxDataValid(i),
            ipDataReady       => ipTxDataReady(i),
            -- Interface to Ethernet frame block
            ethTxDataIn       => multIpTxData(i),
            ethTxDataValid    => multIpTxDataValid(i),
            ethTxDataLastByte => multIpTxDataLastByte(i),
            ethTxDataReady    => multIpTxDataReady(i)
         );
      -- UDP fragmenter to break UDP packets into MTU size chunks
      U_UdpTxFragmenter : entity work.UdpTxFragmenter 
         generic map (
            GATE_DELAY_G => GATE_DELAY_G,
            MTU_SIZE_G   => MTU_SIZE_G,
            ID_OFFSET_G  => conv_std_logic_vector(i*8192,16)
         )
         port map ( 
            -- 125 MHz ethernet clock in
            ethTxClk          => ethClk,
            ethTxRst          => ethRst,
            -- Header data
            ipPacketLength    => ipPacketLength(i),
            ipPacketId        => ipPacketId(i),
            ipMoreFragments   => ipMoreFragments(i),
            ipFragOffset      => ipFragOffset(i),
            ipProtocol        => ipProtocol(i),
            -- User data to be sent
            udpData           => udpTxData(i),
            udpDataValid      => udpTxDataValid(i),
            udpDataReady      => udpTxDataReady(i),
            udpLength         => udpTxLength(i),
            udpReq            => udpTxReq(i),
            udpAck            => udpTxAck(i),
            -- Interface to IPv4 frame block
            ipData            => ipTxData(i),
            ipDataValid       => ipTxDataValid(i),
            ipDataReady       => ipTxDataReady(i)
         );
      -- UDP TX buffer
      U_UdpBufferTx : entity work.UdpBufferTx
         generic map (
            GATE_DELAY_G => GATE_DELAY_G
         )
         port map ( 
            -- User clock and reset (for writes to FIFO)
            userClk           => userClk,
            userRst           => userRst,
            -- 125 MHz clock and reset (for reads from FIFO, interface to Eth blocks)
            ethTxClk          => ethClk,
            ethTxRst          => ethRst,
            -- User data interfaces
            userData          => userTxDataByteOrdered(i),
            userDataValid     => userTxDataValid(i),
            userDataLast      => userTxDataLast(i),
            userDataReady     => userTxDataReady(i),
            -- UDP settings
            udpSrcPort        => udpPorts(i),
            udpDstPort        => udpTxDstPort(i),
            -- Inputs for calculating checksums
            ipSrcAddr         => ipAddrs(i),
--            ipDstAddr         => arpRxSenderIp,
            ipDstAddr         => ipRxSrcAddr,
            -- UDP fragmenter interfaces
            udpData           => udpTxData(i),
            udpDataValid      => udpTxDataValid(i),
            udpDataReady      => udpTxDataReady(i),
            udpLength         => udpTxLength(i),
            udpReq            => udpTxReq(i),
            udpAck            => udpTxAck(i)
         );         
   end generate;
   
   -- IPv4 RX receiver
   U_IPv4Rx : entity work.IPv4Rx 
      generic map (
         GATE_DELAY_G => GATE_DELAY_G
      )
      port map ( 
         -- 125 MHz ethernet clock in
         ethRxClk        => ethClk,
         ethRxRst        => ethRst,
         -- Incoming data from Ethernet frame
         ethRxData       => ethRxData,
         ethRxDataValid  => ethRxDataValid,
         ethRxDataLast   => ethRxDataLast,
         -- Data from the IPv4 header
         ipLength        => ipRxLength,
         ipId            => ipRxId,
         ipMoreFragments => ipRxMoreFragments,
         ipFragOffset    => ipRxFragOffset,
         ipTtl           => ipRxTtl,
         ipProtocol      => ipRxProtocol,
         ipSrcAddr       => ipRxSrcAddr,
         ipDstAddr       => ipRxDstAddr,
         -- Actual data from the payload
         ipData          => ipRxData,
         ipDataValid     => ipRxDataValid,
         ipDataLast      => ipRxDataLast
      ); 

   -- IPv4 RX demuxer
   G_Rx : for i in NUM_IP_G-1 downto 0 generate
      U_UdpBufferRx : entity work.UdpBufferRx
         generic map (
            NUM_IP_G     => NUM_IP_G,
            GATE_DELAY_G => GATE_DELAY_G
         )
         port map ( 
            -- 125 MHz ethernet clock in
            ethRxClk        => ethClk,
            ethRxRst        => ethRst,
            -- Settings for this receiver
            ipAddr          => ipAddrs(i),
            udpPort         => udpPorts(i),
            -- Data from the IPv4 header
            ipLength        => ipRxLength,
            ipId            => ipRxId,
            ipMoreFragments => ipRxMoreFragments,
            ipFragOffset    => ipRxFragOffset,
            ipTtl           => ipRxTtl,
            ipProtocol      => ipRxProtocol,
            ipSrcAddr       => ipRxSrcAddr,
            ipDstAddr       => ipRxDstAddr,
            -- Actual data from the payload
            ipData          => ipRxData,
            ipDataValid     => ipRxDataValid,
            ipDataLast      => ipRxDataLast,
            -- UDP outputs
            udpSrcPort      => udpRxSrcPort(i),
            udpDstPort      => udpRxDstPort(i),
            udpLength       => udpRxLength(i),
            udpChecksum     => udpRxChecksum(i),
            -- UDP payload data interface
            userRxClk       => userClk,
            userRxData      => userRxDataByteOrdered(i),
            userRxDataValid => iUserRxDataValid(i),
            userRxDataLast  => userRxDataLast(i),
            userRxDataReady => userRxDataReady(i)
         ); 
         userRxDataValid(i) <= iUserRxDataValid(i);
   end generate;
   
   -- If you last heard from port X, respond to it
   process(ethClk) begin
      if rising_edge(ethClk) then
         if ethRst = '1' then
            for i in NUM_IP_G-1 downto 0 loop
               udpTxDstPort(i) <= udpPorts(i);
            end loop;
         else 
            for i in NUM_IP_G-1 downto 0 loop
               if udpRxSrcPort(i) /= udpTxDstPort(i) and iUserRxDataValid(i) = '1' then
                  udpTxDstPort(i) <= udpRxSrcPort(i);
               end if;
            end loop;
         end if;
      end if;
   end process;
   
end Behavioral;

