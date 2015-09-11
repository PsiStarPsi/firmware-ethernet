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
 
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--USE ieee.numeric_std.ALL;
 
ENTITY IPv4Test IS
END IPv4Test;
 
ARCHITECTURE behavior OF IPv4Test IS 
 
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
   signal ethTxClk : std_logic := '0';
   signal ethTxRst : std_logic := '0';
   signal ipPacketLength : std_logic_vector(15 downto 0) := x"0020";
   signal ipPacketId : std_logic_vector(15 downto 0) := x"A5B6";
   signal ipMoreFragments : std_logic := '0';
   signal ipFragOffset : std_logic_vector(12 downto 0) := (others => '0');
   signal ipProtocol : std_logic_vector(7 downto 0) := IPV4_PROTO_UDP_C;
   signal ipSrcAddr : IpAddrType := IP_ADDR_DEFAULT_C;
   signal ipDstAddr : IpAddrType := (3 => x"c0", 2 => x"a8", 1 => x"01", 0 => x"02");
   signal ipData : std_logic_vector(31 downto 0) := (others => '0');
   signal ipDataValid : std_logic := '0';
   signal ethTxDataReady : std_logic := '1';

 	--Outputs
   signal ipDataReady : std_logic;
   signal ethTxDataIn : std_logic_vector(7 downto 0);
   signal ethTxDataValid : std_logic;
   signal ethTxDataLastByte : std_logic;

   -- UDP signals
   signal udpData      : slv(31 downto 0);
   signal udpDataValid : sl;
   signal udpDataReady : sl;
   signal udpLength    : slv(15 downto 0);
   signal udpReq       : sl;
   signal udpAck       : sl;   

   -- Signals for ARP interfacing
   signal arpTxSenderMac : MacAddrType;
   signal arpTxSenderIp  : IpAddrType;
   signal arpTxTargetMac : MacAddrType;
   signal arpTxTargetIp  : IpAddrType;
   signal arpTxOp        : slv(15 downto 0);
   signal arpTxReq       : sl;
   signal arpTxAck       : sl;
   signal arpRxOp        : slv(15 downto 0) := x"0001";
   signal arpRxSenderMac : MacAddrType := (5 => x"08", 4 => x"00", 3 => x"27", 2 => x"C9", 1 => x"88", 0 => x"19");
   signal arpRxSenderIp  : IpAddrType := (3 => x"C0", 2 => x"A8", 1 => x"01", 0 => x"02");
   signal arpRxTargetMac : MacAddrType := MAC_ADDR_DEFAULT_C;
   signal arpRxTargetIp  : IpAddrType := IP_ADDR_DEFAULT_C;
   signal arpRxValid     : sl;   
   
   signal macTxData    : EthMacDataType;

   -- User Data signals
   signal userData      : slv(31 downto 0);
   signal userDataValid : sl;
   signal userDataLast  : sl := '0';
   signal userDataReady : sl;
   
   -- Clock period definitions
   constant ethTxClk_period : time := 8 ns;
 
BEGIN

   U_EthTx : entity work.EthTx
      port map ( 
         -- 125 MHz clock and reset
         ethClk         => ethTxClk,
         ethRst         => ethTxRst,
         -- Addressing
         macAddr        => MAC_ADDR_DEFAULT_C,
         -- Connection to GT
         macData        => macTxData,
         -- Connection to upper level ARP 
         arpTxSenderMac => arpTxSenderMac,
         arpTxSenderIp  => arpTxSenderIp,
         arpTxTargetMac => arpTxTargetMac,
         arpTxTargetIp  => arpTxTargetIp,
         arpTxOp        => arpTxOp,
         arpTxReq       => arpTxReq,
         arpTxAck       => arpTxAck,
         -- Connection to IPv4 interface
         ipTxData         => ethTxDataIn,
         ipTxDataValid    => ethTxDataValid,
         ipTxDataLastByte => ethTxDataLastByte,
         ipTxDataReady    => ethTxDataReady         
      );

   -- ARP requester
   ----------------------------
   -- Higher level protocols --
   ----------------------------

   -- ARP : respond to ARP requests based on our IPs
   U_ArpResponder : entity work.ArpResponder 
      port map (
         -- 125 MHz ethernet clock in
         ethClk         => ethTxClk,
         ethRst         => ethTxRst,
         -- Local MAC/IP settings
         macAddress     => MAC_ADDR_DEFAULT_C,
         ipAddresses    => (others => IP_ADDR_DEFAULT_C),
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

 
	-- Instantiate the Unit Under Test (UUT)
   U_IPV4TX : IPv4Tx 
      port map (
         ethTxClk          => ethTxClk,
         ethTxRst          => ethTxRst,
         ipPacketLength    => ipPacketLength,
         ipPacketId        => ipPacketId,
         ipMoreFragments   => ipMoreFragments,
         ipFragOffset      => ipFragOffset,
         ipProtocol        => ipProtocol,
         ipSrcAddr         => ipSrcAddr,
         ipDstAddr         => ipDstAddr,
         ipData            => ipData,
         ipDataValid       => ipDataValid,
         ipDataReady       => ipDataReady,
         ethTxDataIn       => ethTxDataIn,
         ethTxDataValid    => ethTxDataValid,
         ethTxDataLastByte => ethTxDataLastByte,
         ethTxDataReady    => ethTxDataReady
      );

   U_UdpTxFragmenter : entity work.UdpTxFragmenter 
      port map ( 
         -- 125 MHz ethernet clock in
         ethTxClk          => ethTxClk,
         ethTxRst          => ethTxRst,
         -- Header data
         ipPacketLength    => ipPacketLength,
         ipPacketId        => ipPacketId,
         ipMoreFragments   => ipMoreFragments,
         ipFragOffset      => ipFragOffset,
         ipProtocol        => ipProtocol,
         -- User data to be sent
         udpData           => udpData,
         udpDataValid      => udpDataValid,
         udpDataReady      => udpDataReady,
         udpLength         => udpLength,
         udpReq            => udpReq,
         udpAck            => udpAck,
         -- Interface to IPv4 frame block
         ipData            => ipData,
         ipDataValid       => ipDataValid,
         ipDataReady       => ipDataReady
      );        


   U_UdpBufferTx : entity work.UdpBufferTx
      port map ( 
         -- User clock and reset (for writes to FIFO)
         userClk           => ethTxClk,
         userRst           => ethTxRst,
         -- 125 MHz clock and reset (for reads from FIFO, interface to Eth blocks)
         ethTxClk          => ethTxClk,
         ethTxRst          => ethTxRst,
         -- User data interfaces
         userData          => userData,
         userDataValid     => userDataValid,
         userDataLast      => userDataLast,
         userDataReady     => userDataReady,
         -- UDP settings
         udpSrcPort        => x"B00B",
         udpDstPort        => x"ABBA",
         -- Inputs for calculating checksums
         ipSrcAddr         => arpRxTargetIp,
         ipDstAddr         => arpRxSenderIp,
         -- UDP fragmenter interfaces
         udpData           => udpData,
         udpDataValid      => udpDataValid,
         udpDataReady      => udpDataReady,
         udpLength         => udpLength,
         udpReq            => udpReq,
         udpAck            => udpAck
      );


   U_TpGenTx : entity work.TpGenTx
      generic map (
         NUM_WORDS_G => 1000
      )
      port map (
         -- User clock and reset
         userClk         => ethTxClk,
         userRst         => ethTxRst,
         -- Connection to user logic
         userTxData      => userData,
         userTxDataValid => userDataValid,
         userTxDataLast  => userDataLast,
         userTxDataReady => userDataReady
      );
      
   -- Clock process definitions
   ethTxClk_process : process
   begin
		ethTxClk <= '0';
		wait for ethTxClk_period/2;
		ethTxClk <= '1';
		wait for ethTxClk_period/2;
   end process;
 

   -- Stimulus process
   stim_proc: process
   begin		
      -- hold reset state for 100 ns.
      ethTxRst <= '1';
      wait for 100 ns;
      ethTxRst <= '0';
      wait for ethTxClk_period*10;

      -- insert stimulus here 

      wait;
   end process;

   process(ethTxClk) 
      variable arpCount : slv(31 downto 0) := x"00000000";
      variable count : slv(31 downto 0) := x"00000000";
      variable done  : sl := '0';
   begin
      if rising_edge(ethTxClk) then
         if ethTxRst = '1' then
--            userData      <= (others => '0') after 1 ns;
--            userDataValid <= '0' after 1 ns;
            arpRxValid    <= '0' after 1 ns;
            done          := '0';
         else

            if (arpCount = 10 or arpCount = 400) then
               arpRxValid <= '1' after 1 ns;
            else
               arpRxValid <= '0' after 1 ns;
            end if;
            arpCount := arpCount + 1;            
            
--            userDataLast <= '0' after 1 ns;

            if arpCount > 100 then
               if count < 1000 then
                  if count = 999 then
--                     userDataLast <= '1' after 1 ns;
                  end if;
                  if userDataReady = '1' then
                     count := count + 1;
                  end if;
               else
                  done         := '1';
               end if;
--               userDataValid <= not(done) after 1 ns;
--               userData      <= count after 1 ns;
            else
--               userDataValid <= '0';
            end if;
            
         end if;
      end if;
   end process;

   
   
   
   -- process(ethTxClk) 
      -- variable count   : slv(31 downto 0) := x"00000000";
      -- variable done    : sl := '0';
   -- begin
      -- if rising_edge(ethTxClk) then
         -- if ethTxRst = '1' then
            -- udpData      <= (others => '0');
            -- udpDataValid <= '0';
            -- udpLength    <= conv_std_logic_vector(8000,udpLength'length);
            -- arpRxValid   <= '0';
            -- done         := '0';
         -- else
            -- if (count = 2) then
               -- arpRxValid <= '1';
            -- else
               -- arpRxValid <= '0';
            -- end if;
            -- udpData      <= count;
            -- udpDataValid <= not(done);
            -- udpReq       <= not(done);
            -- if udpDataReady = '1' then
               -- count := count + 1;
            -- end if;
            -- if (udpAck = '1') then
               -- done := '1';
            -- end if;
         -- end if;
      -- end if;
   -- end process;


   
END;
