--------------------------------------------------------------------------------
-- Company: 
-- Engineer:
--
-- Create Date:   00:50:52 08/18/2015
-- Design Name:   
-- Module Name:   C:/Users/Kurtis/Desktop/testBed/ethernet/TxRxSim.vhd
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
 
ENTITY TxRxSim IS
END TxRxSim;
 
ARCHITECTURE behavior OF TxRxSim IS     

   --Inputs
   signal ethClk : std_logic := '0';
   signal ethRst : std_logic := '0';
   
   
   signal userData         : std_logic_vector(7 downto 0) := (others => '0');
   signal userDataValid    : std_logic := '0';
   signal userDataLastByte : std_logic := '0';
   --signal userDataCount    : std_logic_vector(10 downto 0) := (others => '0');
   signal idleCount        : std_logic_vector(10 downto 0) := (others => '0');
   
   signal macData        : EthMacDataType;
  
   signal txMacAddress   : MacAddrType := MAC_ADDR_DEFAULT_C;
   signal rxMacAddress   : MacAddrType := ( 5 => x"A1",
                                            4 => x"B2",
                                            3 => x"C3",
                                            2 => x"D4",
                                            1 => x"E5",
                                            0 => x"F6" );
   signal txEtherType    : EtherType := ETH_TYPE_ARP_C;

   signal txIpAddress   : IpAddrType := ( 3 => conv_std_logic_vector(192,8),
                                          2 => conv_std_logic_vector(168,8),
                                          1 => conv_std_logic_vector(1,8),
                                          0 => conv_std_logic_vector(2,8) );
   signal rxIpAddress   : IpAddrType := IP_ADDR_DEFAULT_C;
   
   -- MAC frame TX
   signal macTxData         : std_logic_vector(7 downto 0) := (others => '0');
   signal macTxDataValid    : std_logic := '0';
   signal macTxDataLastByte : std_logic := '0';
   signal macTxDataReady    : std_logic := '0';
   -- Ethernet frame TX
   signal ethTxData         : std_logic_vector(7 downto 0) := (others => '0');
   signal ethTxDataValid    : std_logic := '0';
   signal ethTxDataLastByte : std_logic := '0';
   signal ethTxDataReady    : std_logic := '0';
   -- ARP TX interfave
   signal arpReq : std_logic := '0';
   signal arpAck : std_logic := '0';
   
   -- MAC frame RX
   signal macRxData      : std_logic_vector(7 downto 0) := (others => '0');
   signal macRxDataValid : std_logic := '0';
   signal macRxDataLast  : std_logic := '0';
   signal macRxBadFrame  : std_logic := '0';   
 	-- Ethernet frame RX
   signal ethRxEtherType : EtherType   := ETH_TYPE_INIT_C;
   signal ethRxSrcMac    : MacAddrType := MAC_ADDR_INIT_C;
   signal ethRxDestMac   : MacAddrType := MAC_ADDR_INIT_C;
   signal ethRxData      : std_logic_vector(7 downto 0);
   signal ethRxDataValid : std_logic;
   signal ethRxDataLast  : std_logic;
   -- ARP packet RX
   signal arpSenderMac   : MacAddrType;
   signal arpSenderIp    : IpAddrType;
   signal arpTargetMac   : MacAddrType;
   signal arpTargetIp    : IpAddrType;
   signal arpValid       : sl;
   
   -- Clock period definitions
   constant ethClk_period : time := 8 ns;
   constant GATE_DELAY_C  : time := 1 ns;
   
BEGIN

   -- Transmit data from Tx
   U_MacTx : entity work.Eth1000BaseXMacTx
      port map (
         -- 125 MHz ethernet clock in
         ethTxClk         => ethClk, 
         ethTxRst         => ethRst,
         -- User data to be sent
         userDataIn       => macTxData,
         userDataValid    => macTxDataValid,
         userDataLastByte => macTxDataLastByte,
         userDataReady    => macTxDataReady,
         -- Data out to the GTX
         macDataOut       => macData
      );

   -- Ethernet Type II Frame Transmitter
   U_EthFrameTx : entity work.EthFrameTx 
      port map ( 
         -- 125 MHz ethernet clock in
         ethTxClk          => ethClk,
         ethTxRst          => ethRst,
         -- Data for the header
         ethTxDestMac      => rxMacAddress,
         ethTxSrcMac       => txMacAddress,
         ethTxEtherType    => txEtherType,
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
   port map ( 
      -- 125 MHz ethernet clock in
      ethTxClk          => ethClk,
      ethTxRst          => ethRst,
      -- Data to send
      arpSenderMac      => txMacAddress,
      arpSenderIp       => txIpAddress,
      arpTargetMac      => rxMacAddress,
      arpTargetIp       => rxIpAddress,
      arpOp             => ARP_OP_REQ_C,
      arpReq            => arpReq,
      arpAck            => arpAck,
      -- User data to be sent
      ethTxData         => ethTxData,
      ethTxDataValid    => ethTxDataValid,
      ethTxDataLastByte => ethTxDataLastByte,
      ethTxDataReady    => ethTxDataReady
   );

   ------------------------------------------------------------------

   -- Receive into the Rx
   U_MacRx : entity work.Eth1000BaseXMacRx
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
      port map (
         ethRxClk       => ethClk,
         ethRxRst       => ethRst,
         macAddress     => rxMacAddress,
         macRxData      => macRxData,
         macRxDataValid => macRxDataValid,
         macRxDataLast  => macRxDataLast,
         macRxBadFrame  => macRxBadFrame,
         ethRxEtherType => ethRxEtherType,
         ethRxSrcMac    => ethRxSrcMac,
         ethRxDestMac   => ethRxDestMac,
         ethRxData      => ethRxData,
         ethRxDataValid => ethRxDataValid,
         ethRxDataLast  => ethRxDataLast
      );

	-- ARP Packet Receiver
   U_ArpPacketRx : entity work.ArpPacketRx 
      port map (
         ethRxClk       => ethClk,
         ethRxRst       => ethRst,
         ethRxSrcMac    => ethRxSrcMac,
         ethRxDestMac   => ethRxDestMac,
         ethRxData      => ethRxData,
         ethRxDataValid => ethRxDataValid,
         ethRxDataLast  => ethRxDataLast,
         -- Received data from ARP packet
         arpSenderMac   => arpSenderMac,
         arpSenderIp    => arpSenderIp,
         arpTargetMac   => arpTargetMac,
         arpTargetIp    => arpTargetIp, 
         arpValid       => arpValid
      );

      
   -- Clock process definitions
   ethRxClk_process :process
   begin
		ethClk <= '0';
		wait for ethClk_period/2;
		ethClk <= '1';
		wait for ethClk_period/2;
   end process;

   -- Stimulus process
   stim_proc: process
   begin		

      ethRst <= '1';

      -- hold reset state for 100 ns.
      wait for 100 ns;	

      ethRst <= '0';
      
      wait for ethClk_period*10;

      -- insert stimulus here 
      
      wait;
   end process;

   data_proc : process(ethClk) begin
      if rising_edge(ethClk) then
         if ethRst = '1' then
            arpReq <= '0';
            idleCount        <= (others => '0') after GATE_DELAY_C;
         else
            if (idleCount = 10) then
               arpReq <= '1';
               if (arpAck = '1') then
                  arpReq <= '0';
--                  idleCount <= (others => '0');
                  idleCount <= idleCount + 1;
               end if;
				elsif idleCount < 10 then
               idleCount <= idleCount + 1;
            end if;
         end if;
      end if;
   end process;
   
   -- data_proc : process(ethClk) 
      -- variable userDataCount : slv(10 downto 0) := (others => '0');
   -- begin
      -- if rising_edge(ethClk) then
         -- if ethRst = '1' then
            -- userData         <= (others => '0') after GATE_DELAY_C;
            -- userDataValid    <= '0'             after GATE_DELAY_C;
            -- userDataLastByte <= '0'             after GATE_DELAY_C;
            -- userDataCount    := (others => '0');-- after GATE_DELAY_C;
            -- idleCount        <= (others => '0') after GATE_DELAY_C;
         -- else
            -- if (userDataReady = '1') then
               -- userDataCount := userDataCount + 1;
            -- end if;
            -- if (idleCount > 10) then
               -- userDataValid    <= '1' after GATE_DELAY_C;
               -- userDataLastByte <= '0' after GATE_DELAY_C;
               -- -- if    (userDataCount =  0) then userData <= rxMacAddress(0);
               -- -- elsif (userDataCount =  1) then userData <= rxMacAddress(1);
               -- -- elsif (userDataCount =  2) then userData <= rxMacAddress(2);
               -- -- elsif (userDataCount =  3) then userData <= rxMacAddress(3);
               -- -- elsif (userDataCount =  4) then userData <= rxMacAddress(4);
               -- -- elsif (userDataCount =  5) then userData <= rxMacAddress(5);
               -- -- elsif (userDataCount =  6) then userData <= txMacAddress(0);
               -- -- elsif (userDataCount =  7) then userData <= txMacAddress(1);
               -- -- elsif (userDataCount =  8) then userData <= txMacAddress(2);
               -- -- elsif (userDataCount =  9) then userData <= txMacAddress(3);
               -- -- elsif (userDataCount = 10) then userData <= txMacAddress(4);
               -- -- elsif (userDataCount = 11) then userData <= txMacAddress(5);
               -- --elsif    (userDataCount =  0) then userData <= getByte(1,ETH_TYPE_ARP_C);
               -- --elsif (userDataCount =  1) then userData <= getByte(0,ETH_TYPE_ARP_C);
               -- if    (userDataCount =  0) then userData <= getByte(1,ARP_HTYPE_C);
               -- elsif (userDataCount =  1) then userData <= getByte(0,ARP_HTYPE_C);
               -- elsif (userDataCount =  2) then userData <= getByte(1,ARP_PTYPE_C);
               -- elsif (userDataCount =  3) then userData <= getByte(0,ARP_PTYPE_C);
               -- elsif (userDataCount =  4) then userData <= getByte(0,ARP_HLEN_C);
               -- elsif (userDataCount =  5) then userData <= getByte(0,ARP_PLEN_C);
               -- elsif (userDataCount =  6) then userData <= getByte(1,ARP_OP_REQ_C);
               -- elsif (userDataCount =  7) then userData <= getByte(0,ARP_OP_REQ_C);
               -- elsif (userDataCount =  8) then userData <= txMacAddress(5);
               -- elsif (userDataCount =  9) then userData <= txMacAddress(4);
               -- elsif (userDataCount = 10) then userData <= txMacAddress(3);
               -- elsif (userDataCount = 11) then userData <= txMacAddress(2);
               -- elsif (userDataCount = 12) then userData <= txMacAddress(1);
               -- elsif (userDataCount = 13) then userData <= txMacAddress(0);
               -- elsif (userDataCount = 14) then userData <= txIpAddress(3);
               -- elsif (userDataCount = 15) then userData <= txIpAddress(2);
               -- elsif (userDataCount = 16) then userData <= txIpAddress(1);
               -- elsif (userDataCount = 17) then userData <= txIpAddress(0);
               -- elsif (userDataCount = 18) then userData <= MAC_ADDR_BCAST_C(5);
               -- elsif (userDataCount = 19) then userData <= MAC_ADDR_BCAST_C(4);
               -- elsif (userDataCount = 20) then userData <= MAC_ADDR_BCAST_C(3);
               -- elsif (userDataCount = 21) then userData <= MAC_ADDR_BCAST_C(2);
               -- elsif (userDataCount = 22) then userData <= MAC_ADDR_BCAST_C(1);
               -- elsif (userDataCount = 23) then userData <= MAC_ADDR_BCAST_C(0);
               -- elsif (userDataCount = 24) then userData <= rxIpAddress(3);
               -- elsif (userDataCount = 25) then userData <= rxIpAddress(2);
               -- elsif (userDataCount = 26) then userData <= rxIpAddress(1);
               -- elsif (userDataCount = 27) then userData <= rxIpAddress(0);
                                               -- userDataLastByte <= '1';
               -- else
                  -- userDataValid <= '0'             after GATE_DELAY_C;
-- --                  idleCount     <= (others => '0') after GATE_DELAY_C;
                  -- userDataCount := (others => '0');-- after GATE_DELAY_C;
               -- end if;
            -- else
               -- idleCount     <= idleCount + 1 after GATE_DELAY_C;
            -- end if;
         -- end if;
      -- end if;
   -- end process;
   
END;
