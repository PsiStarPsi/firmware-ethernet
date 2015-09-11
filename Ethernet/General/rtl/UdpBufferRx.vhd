---------------------------------------------------------------------------------
-- Title         : UDP Buffer RX
-- Project       : General Purpose Core
---------------------------------------------------------------------------------
-- File          : UdpBufferRx.vhd
-- Author        : Kurtis Nishimura
---------------------------------------------------------------------------------
-- Description:
-- Connects to IPv4 receiver, demuxes to RX FIFOs for each IP address.
---------------------------------------------------------------------------------

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.GigabitEthPkg.all;

entity UdpBufferRx is 
   generic (
      NUM_IP_G       : integer := 1;
      GATE_DELAY_G   : time := 1 ns
   );
   port ( 
      -- 125 MHz ethernet clock in
      ethRxClk        : in  sl;
      ethRxRst        : in  sl := '0';
      -- Settings for this receiver
      ipAddr          : in  IpAddrType;
      udpPort         : in  slv(15 downto 0);
      -- Data from the IPv4 header
      ipLength        : in  slv(15 downto 0);
      ipId            : in  slv(15 downto 0);
      ipMoreFragments : in  sl;
      ipFragOffset    : in  slv(12 downto 0);
      ipTtl           : in  slv( 7 downto 0);
      ipProtocol      : in  slv( 7 downto 0);
      ipSrcAddr       : in  IpAddrType;
      ipDstAddr       : in  IpAddrType;
      -- Actual data from the payload
      ipData          : in  slv(31 downto 0);
      ipDataValid     : in  sl;
      ipDataLast      : in  sl;
      -- UDP outputs
      udpSrcPort      : out slv(15 downto 0);
      udpDstPort      : out slv(15 downto 0);
      udpLength       : out slv(15 downto 0);
      udpChecksum     : out slv(15 downto 0);
      -- UDP payload data interface
      userRxClk       : in  sl;
      userRxData      : out slv(31 downto 0);
      userRxDataValid : out sl;
      userRxDataLast  : out sl;
      userRxDataReady : in  sl
   ); 
end UdpBufferRx;

-- Define architecture
architecture rtl of UdpBufferRx is

   type StateType     is (IDLE_AND_HEADER_0_S, HEADER_1_S, 
                          PAYLOAD_S, DUMP_S);
   
   type RegType is record
      state           : StateType;
      myIpAddr        : IpAddrType;
      myUdpPort       : slv(15 downto 0);
      ipLength        : slv(15 downto 0);
      ipId            : slv(15 downto 0);
      ipMoreFragments : sl;
      ipFragOffset    : slv(12 downto 0);
      ipTtl           : slv( 7 downto 0);
      ipProtocol      : slv( 7 downto 0);
      ipSrcAddr       : IpAddrType;
      ipDstAddr       : IpAddrType;
      udpSrcPort      : slv(15 downto 0);
      udpDstPort      : slv(15 downto 0);
      udpLength       : slv(15 downto 0);
      udpChecksum     : slv(15 downto 0);
      fifoWrData      : slv(31 downto 0);
      fifoWrDataValid : sl;
      fifoWrDataLast  : sl;
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      state           => IDLE_AND_HEADER_0_S,
      myIpAddr        => IP_ADDR_INIT_C,
      myUdpPort       => (others => '0'),
      ipLength        => (others => '0'),
      ipId            => (others => '0'),
      ipMoreFragments => '0',
      ipFragOffset    => (others => '0'),
      ipTtl           => (others => '0'),
      ipProtocol      => (others => '0'),
      ipSrcAddr       => IP_ADDR_INIT_C,
      ipDstAddr       => IP_ADDR_INIT_C,
      udpSrcPort      => (others => '0'),
      udpDstPort      => (others => '0'),
      udpLength       => (others => '0'),
      udpChecksum     => (others => '0'),
      fifoWrData      => (others => '0'),
      fifoWrDataValid => '0',
      fifoWrDataLast  => '0'
   );
   
   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   -- ISE attributes to keep signals for debugging
   -- attribute keep : string;
   -- attribute keep of r : signal is "true";
   -- attribute keep of crcOut : signal is "true";      
   
   -- Vivado attributes to keep signals for debugging
   -- attribute dont_touch : string;
   -- attribute dont_touch of r : signal is "true";
   -- attribute dont_touch of crcOut : signal is "true";   
   
   signal fifoWrDataReady : sl;
   
begin

   ------------------------------------------
   -- FIFO to write valid UDP payload into --
   ------------------------------------------
   U_UdpRxAxiFifo : entity work.fifo32x512RxAxi
      PORT MAP (
         m_aclk        => userRxClk,
         s_aclk        => ethRxClk,
         s_aresetn     => not(ethRxRst),
         s_axis_tvalid => r.fifoWrDataValid,
         s_axis_tready => fifoWrDataReady,
         s_axis_tdata  => r.fifoWrData,
         s_axis_tlast  => r.fifoWrDataLast,
         m_axis_tvalid => userRxDataValid,
         m_axis_tready => userRxDataReady,
         m_axis_tdata  => userRxData,
         m_axis_tlast  => userRxDataLast
      );

   ------------------------------------------
   -- State machine to locate valid data   --
   ------------------------------------------   
   comb : process(r,ethRxRst,ipAddr,udpPort,ipLength,ipId,ipMoreFragments,
                  ipFragOffset,ipTtl,ipProtocol,ipSrcAddr,ipDstAddr,
                  ipData,ipDataValid,ipDataLast,fifoWrDataReady) is
      variable v : RegType;
   begin
      v := r;

      -- Resets for pulsed outputs
      
      -- Register incoming data
      v.fifoWrDataValid := '0';
      v.fifoWrDataLast  := '0';
      
      -- State machine for interpreting 32-bit data
      case(r.state) is 
         when IDLE_AND_HEADER_0_S =>
            if ipDataValid = '1' and ipDataLast /= '1' then
               v.myIpAddr        := ipAddr;
               v.myUdpPort       := udpPort;
               v.ipLength        := ipLength;
               v.ipId            := ipId;
               v.ipMoreFragments := ipMoreFragments;
               v.ipFragOffset    := ipFragOffset;
               v.ipTtl           := ipTtl;
               v.ipProtocol      := ipProtocol;
               v.ipSrcAddr       := ipSrcAddr;
               v.ipDstAddr       := ipDstAddr;
               v.udpSrcPort      := ipData(31 downto 16);
               v.udpDstPort      := ipData(15 downto  0);
               v.state           := HEADER_1_S;
            end if;
         when HEADER_1_S =>
            -- Dump out of the event if ports don't match, IPs don't match,
            -- or if this is our last data 
            if ipDataValid = '1' then
               -- Dump if this is an incomplete packet...
               if ipDataLast = '1' then
                  v.state := IDLE_AND_HEADER_0_S;
               -- Or if it turns out it wasn't UDP...
               -- Or if the IP addresses don't match...
               -- Or if the UDP ports don't match...
               elsif ( (r.ipProtocol /= IPV4_PROTO_UDP_C) or 
                       (r.udpDstPort /= r.myUdpPort) or
                       (r.ipDstAddr  /= r.myIpAddr) ) then
                  v.state := DUMP_S;
               -- Otherwise we have a good packet
               else 
                  v.udpLength   := ipData(31 downto 16);
                  v.udpChecksum := ipData(15 downto  0);
                  v.state       := PAYLOAD_S;
               end if;
            end if;
         when PAYLOAD_S =>
            v.fifoWrData      := ipData;
            v.fifoWrDataValid := ipDataValid;
            v.fifoWrDataLast  := ipDataLast;
            if ipDataValid = '1' and ipDataLast = '1' then
               v.state := IDLE_AND_HEADER_0_S;
            end if;
         when DUMP_S =>
            if ipDataValid = '1' and ipDataLast = '1' then
               v.state := IDLE_AND_HEADER_0_S;
            end if;
         -- Others
         when others =>
            v.state := IDLE_AND_HEADER_0_S;
      end case;


      -- Reset logic
      if (ethRxRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Outputs to ports
      udpSrcPort  <= r.udpSrcPort;
      udpDstPort  <= r.udpDstPort;
      udpLength   <= r.udpLength;
      udpChecksum <= r.udpChecksum;
      
      -- Assignment of combinatorial variable to signal
      rin <= v;

   end process;

   seq : process (ethRxClk) is
   begin
      if (rising_edge(ethRxClk)) then
         r <= rin after GATE_DELAY_G;
      end if;
   end process seq;   

end rtl;

