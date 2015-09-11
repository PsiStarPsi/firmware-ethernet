---------------------------------------------------------------------------------
-- Title         : UDP Packet Buffer and Transmitter
-- Project       : General Purpose Core
---------------------------------------------------------------------------------
-- File          : UdpBufferTx.vhd
-- Author        : Kurtis Nishimura
---------------------------------------------------------------------------------
-- Description:
-- Arbitrary 32-bit data input accepted from user clock domain.
-- Data is read out in the ethernet 125 MHz domain.
-- Buffers up an entire UDP packet (so that it 
-- can generate header information), and then interfaces to the UdpTxFragmenter,
-- which breaks the data up into MTU-size chunks.
---------------------------------------------------------------------------------

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.GigabitEthPkg.all;

entity UdpBufferTx is 
   generic (
      GATE_DELAY_G : time := 1 ns
   );
   port ( 
      -- User clock and reset (for writes to FIFO)
      userClk           : in  sl;
      userRst           : in  sl;
      -- 125 MHz clock and reset (for reads from FIFO, interface to Eth blocks)
      ethTxClk          : in  sl;
      ethTxRst          : in  sl := '0';
      -- User data interfaces
      userData          : in  slv(31 downto 0);
      userDataValid     : in  sl;
      userDataLast      : in  sl;
      userDataReady     : out sl;
      -- UDP settings
      udpSrcPort        : in  slv(15 downto 0);
      udpDstPort        : in  slv(15 downto 0);
      -- Inputs for calculating checksums
      ipSrcAddr         : in  IpAddrType;
      ipDstAddr         : in  IpAddrType;
      -- UDP fragmenter interfaces
      udpData           : out slv(31 downto 0);
      udpDataValid      : out sl;
      udpDataReady      : in  sl;
      udpLength         : out slv(15 downto 0);
      udpReq            : out sl;
      udpAck            : in  sl
   );
end UdpBufferTx;

architecture rtl of UdpBufferTx is

   type UserStateType is (IDLE_S, COUNTING_S);
   
   type UserRegType is record
      state        : UserStateType;
      payloadBytes : slv(15 downto 0);
      sizeWrEn     : sl;
   end record UserRegType;
   
   constant USER_REG_INIT_C : UserRegType := (
      state        => IDLE_S,
      payloadBytes => (others => '0'),
      sizeWrEn     => '0'
   );
   
   signal rUser   : UserRegType := USER_REG_INIT_C;
   signal rinUser : UserRegType;
   
   -- ISE attributes to keep signals for debugging
   -- attribute keep : string;
   -- attribute keep of rUser : signal is "true";      
   
   -- Vivado attributes to keep signals for debugging
   -- attribute dont_touch : string;
   -- attribute dont_touch of rUser : signal is "true";

   type EthStateType  is (WAIT_PACKET_S, 
                          HEADER_0_S, HEADER_1_S, READ_DATA_S);
   
   type EthRegType is record
      state        : EthStateType;
      ipSrcAddr    : IpAddrType;
      ipDstAddr    : IpAddrType;
      udpSrcPort   : slv(15 downto 0);
      udpDstPort   : slv(15 downto 0);
      udpData      : slv(31 downto 0);
      udpDataValid : sl;
      udpLength    : slv(15 downto 0);
      udpReq       : sl;
      sizeFifoRdEn : sl;
      bytesLeft    : slv(15 downto 0);
      udpFifoRdEn  : sl;
   end record EthRegType;
   
   constant ETH_REG_INIT_C : EthRegType := (
      state        => WAIT_PACKET_S,
      ipSrcAddr    => IP_ADDR_INIT_C,
      ipDstAddr    => IP_ADDR_INIT_C,
      udpSrcPort   => (others => '0'),
      udpDstPort   => (others => '0'),
      udpData      => (others => '0'),
      udpDataValid => '0',
      udpLength    => (others => '0'),
      udpReq       => '0',
      sizeFifoRdEn => '0',
      bytesLeft    => (others => '0'),
      udpFifoRdEn  => '0'
   );

   signal rEth   : EthRegType := ETH_REG_INIT_C;
   signal rinEth : EthRegType;

   -- ISE attributes to keep signals for debugging
   -- attribute keep : string;
   -- attribute keep of rEth : signal is "true";      
   
   -- Vivado attributes to keep signals for debugging
   -- attribute dont_touch : string;
   -- attribute dont_touch of rEth : signal is "true";
   
   -- Other signals used for interfacing to sub-blocks
   signal udpFifoAlmostFull  : sl;
   signal udpFifoWrEn        : sl;
   signal udpFifoRdData      : slv(31 downto 0);
   signal udpFifoRdDataValid : sl;
   signal udpFifoEmpty       : sl;
   signal udpFifoRdEn        : sl;
   
   signal sizeFifoEmpty      : sl;
   signal sizeFifoRdData     : slv(15 downto 0);
   signal sizeFifoAlmostFull : sl;
   
begin


   -- UDP data gets written into this FIFO from
   -- user clock domain, read out in ethernet clock
   -- domain.
   -- This fifo has FWFT enabled.
   U_Udp64KFifo : entity work.udp64kfifo
      port map (
         rst         => userRst,
         wr_clk      => userClk,
         rd_clk      => ethTxClk,
         din         => userData,
         wr_en       => udpFifoWrEn,
         rd_en       => udpFifoRdEn,
         dout        => udpFifoRdData,
         full        => open,
         almost_full => udpFifoAlmostFull,
         empty       => udpFifoEmpty,
         valid       => udpFifoRdDataValid
      );
   userDataReady <= not(udpFifoAlmostFull) and not(sizeFifoAlmostFull);
   udpFifoWrEn   <= not(udpFifoAlmostFull) and not(sizeFifoAlmostFull) and userDataValid;

   U_UdpSizeFifo : entity work.fifo16x64
      port map (
         rst         => userRst,
         wr_clk      => userClk,
         rd_clk      => ethTxClk,
         din         => rUser.payloadBytes,
         wr_en       => rUser.sizeWrEn,
         rd_en       => rEth.sizeFifoRdEn,
         dout        => sizeFifoRdData,
         full        => open,
         almost_full => sizeFifoAlmostFull,
         empty       => sizeFifoEmpty
      );
   
   ------------------------------------------------
   
   combUser : process(rUser,userRst,userData,userDataValid,userDataLast,
                      udpFifoAlmostFull, udpFifoWrEn) is
      variable v : UserRegType;
   begin
      v := rUser;

      -- Set defaults / reset any pulsed signals
      v.sizeWrEn := '0';
      
      -- State machine
      case(rUser.state) is 
         when IDLE_S =>
            v.payloadBytes := (others => '0');
            if udpFifoWrEn = '1' then
               v.payloadBytes := x"0004";
               if userDataLast = '1' then
                  v.sizeWrEn := '1';
                  v.state    := IDLE_S;
               else
                  v.state := COUNTING_S;
               end if;
            end if;
         when COUNTING_S =>
            if udpFifoWrEn = '1' then
               v.payloadBytes := rUser.payloadBytes + 4;
               if userDataLast = '1' then
                  v.sizeWrEn     := '1';
                  v.state        := IDLE_S;
               end if;
            end if; 
         when others =>
            v.state := IDLE_S;
      end case;
         
      -- Reset logic
      if (userRst = '1') then
         v := USER_REG_INIT_C;
      end if;

      -- Outputs to ports

      -- Assign variable to signal
      rinUser <= v;

   end process combUser;

   seqUser : process (userClk) is
   begin
      if (rising_edge(userClk)) then
         rUser <= rinUser after GATE_DELAY_G;
      end if;
   end process seqUser;

   ------------------------------------------------
   
   combEth : process(rEth,ethTxRst,udpSrcPort,udpDstPort,ipSrcAddr,ipDstAddr,
                     udpDataReady, udpAck, udpFifoRdData, udpFifoRdDataValid,
                     sizeFifoEmpty, sizeFifoRdData) is
      variable v : EthRegType;
   begin
      v := rEth;

      -- Set defaults / reset any pulsed signals
      v.sizeFifoRdEn := '0';
      v.udpFifoRdEn  := '0';
      udpDataValid   <= '0';
      udpFifoRdEn    <= '0';
      udpData        <= (others => '0');
      
      -- State machine
      case(rEth.state) is 
         when WAIT_PACKET_S =>
            if sizeFifoEmpty = '0' then
               v.ipSrcAddr    := ipSrcAddr;
               v.ipDstAddr    := ipDstAddr;
               v.udpSrcPort   := udpSrcPort;
               v.udpDstPort   := udpDstPort;
               v.udpLength    := sizeFifoRdData + 8;
               v.bytesLeft    := sizeFifoRdData - 4;
               v.sizeFifoRdEn := '1';
               v.state        := HEADER_0_S;
            end if;
         when HEADER_0_S =>
            udpData      <= rEth.udpSrcPort & rEth.udpDstPort;
            udpDataValid <= '1';
            if udpDataReady = '1' then
               v.state := HEADER_1_S;
            end if;
         when HEADER_1_S =>
            udpData        <= rEth.udpLength & x"0000";
            udpDataValid   <= '1';
            if udpDataReady = '1' then
               v.state := READ_DATA_S;
            end if;
         when READ_DATA_S =>
            udpData        <= udpFifoRdData;
            udpDataValid   <= udpFifoRdDataValid;
            udpFifoRdEn    <= udpDataReady and udpFifoRdDataValid;
            if udpFifoRdDataValid = '1' and udpDataReady = '1' then
               v.bytesLeft   := rEth.bytesLeft - 4;
               if rEth.bytesLeft = 0 then
                  v.state := WAIT_PACKET_S;
               end if;
            end if;
         when others =>
            v.state := WAIT_PACKET_S;
      end case;
         
      -- Reset logic
      if (ethTxRst = '1') then
         v := ETH_REG_INIT_C;
      end if;

      -- Outputs to ports
--      udpData      <= rEth.udpData;
--      udpDataValid <= rEth.udpDataValid;
      udpLength    <= rEth.udpLength;
      udpReq       <= rEth.udpReq;
      
      -- Assign variable to signal
      rinEth <= v;

   end process combEth;

   seqEth : process (ethTxClk) is
   begin
      if (rising_edge(ethTxClk)) then
         rEth <= rinEth after GATE_DELAY_G;
      end if;
   end process seqEth;   
   
end rtl;
