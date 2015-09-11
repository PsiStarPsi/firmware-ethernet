-------------------------------------------------------------------------------
-- Title         : Gigabit Ethernet Package
-- Project       : General Purpose Core
-------------------------------------------------------------------------------
-- File          : GigabitEthPkg.vhd
-- Author        : Kurtis Nishimura
-------------------------------------------------------------------------------
-- Description:
-- Gigabit ethernet constants & types.
-------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
use work.UtilityPkg.all;

package GigabitEthPkg is

   -----------------------------------------------------
   -- Constants
   -----------------------------------------------------
   
   -- Ethernet constants
   constant ETH_PRE_C : slv(7 downto 0) := x"55"; -- Preamble
   constant ETH_SOF_C : slv(7 downto 0) := x"D5"; -- Start of Frame
   constant ETH_PAD_C : slv(7 downto 0) := x"00"; -- Padding bytes
   
   -- Minimum payload size for Ethernet frame in bytes
   -- (starting from destination MAC and going through data)
   constant ETH_MIN_SIZE_C : integer := 64;

   -- This is the value you should get if you apply the CRC value to the packet
   -- over which it is applied.  It will be a constant value for correct CRC.
   constant CRC_CHECK_C : slv(31 downto 0) := x"1CDF4421";

   type EthMacDataType is record
      data      : slv(7 downto 0);
      dataK     : sl;
      dataValid : sl;
   end record EthMacDataType;
   
   ---------------------------------------------------------------------------------------------

   -- Type for IP address
   type IPAddrType is array(3 downto 0) of std_logic_vector(7 downto 0);
   constant IP_ADDR_DEFAULT_C : IPAddrType := (3 => x"C0", 2 => x"A8", 1 => x"01", 0 => x"14"); --192.168.1.20
   constant IP_ADDR_INIT_C    : IPAddrType := (others => (others => '0'));
   -- Array of IP addresses 
   type IpAddrArray is array(natural range<>) of IpAddrType;
   
   -- Type for mac address
   type MacAddrType is array(5 downto 0) of std_logic_vector(7 downto 0);
   constant MAC_ADDR_DEFAULT_C : MacAddrType := (5 => x"00", 4 => x"44", 3 => x"56", 2 => x"00", 1 => x"03", 0 => x"01");
   constant MAC_ADDR_BCAST_C   : MacAddrType := (others => (others => '1'));
   constant MAC_ADDR_INIT_C    : MacAddrType := (others => (others => '0'));
   
   -- Ethernet header field constants
   subtype EtherType is std_logic_vector(15 downto 0);
   constant ETH_TYPE_INIT_C : EtherType := x"0000";
   constant ETH_TYPE_IPV4_C : EtherType := x"0800";
   constant ETH_TYPE_ARP_C  : EtherType := x"0806";
   -- Not implemented at the moment but maybe in the future
   --constant EthTypeIPV6 : EtherType := x"86DD";
   --constant EthTypeMac  : EtherType := x"8808";

   -- UDP header field constants
   subtype ProtocolType is std_logic_vector(7 downto 0);
   constant UDP_PROTOCOL_C : ProtocolType := x"11";
   -- Not implemented at the moment but maybe in the future
   --constant ICMP_PROTOCOL_C : ProtocolType := x"01";
   --constant TCP_PROTOCOL_C  : ProtocolType := x"06";

   -- ARP constants
   constant ARP_HTYPE_C  : slv(15 downto 0) := x"0001";
   constant ARP_PTYPE_C  : slv(15 downto 0) := x"0800";
   constant ARP_HLEN_C   : slv( 7 downto 0) := x"06";
   constant ARP_PLEN_C   : slv( 7 downto 0) := x"04";
   constant ARP_OP_REQ_C : slv(15 downto 0) := x"0001";
   constant ARP_OP_RES_C : slv(15 downto 0) := x"0002";
   
   -- IPv4 constants
   constant IPV4_VERSION_C    : slv(3 downto 0) := x"4";
   constant IPV4_IHL_C        : slv(3 downto 0) := x"5";
   constant IPV4_DSCP_C       : slv(5 downto 0) := (others => '0');
   constant IPV4_ECN_C        : slv(1 downto 0) := (others => '0');
   constant IPV4_TTL_C        : slv(7 downto 0) := x"02";
   constant IPV4_PROTO_UDP_C  : slv(7 downto 0) := x"11";
   constant IPV4_PROTO_ICMP_C : slv(7 downto 0) := x"01";
   
end GigabitEthPkg;

package body GigabitEthPkg is
      
end package body GigabitEthPkg;
