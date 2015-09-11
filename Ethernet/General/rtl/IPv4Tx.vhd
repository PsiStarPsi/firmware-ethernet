---------------------------------------------------------------------------------
-- Title         : ARP Packet TX
-- Project       : General Purpose Core
---------------------------------------------------------------------------------
-- File          : IPv4Tx.vhd
-- Author        : Kurtis Nishimura
---------------------------------------------------------------------------------
-- Description:
-- Connects to Ethernet layer, sends IPv4 packets
---------------------------------------------------------------------------------

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.GigabitEthPkg.all;

entity IPv4Tx is 
   generic (
      GATE_DELAY_G : time := 1 ns
   );
   port ( 
      -- 125 MHz ethernet clock in
      ethTxClk          : in  sl;
      ethTxRst          : in  sl := '0';
      -- Header data
      ipPacketLength    : in  slv(15 downto 0);
      ipPacketId        : in  slv(15 downto 0);
      ipMoreFragments   : in  sl;
      ipFragOffset      : in  slv(12 downto 0);
      ipProtocol        : in  slv( 7 downto 0);
      ipSrcAddr         : in  IpAddrType;
      ipDstAddr         : in  IpAddrType;
      -- User data to be sent
      ipData            : in  slv(31 downto 0);
      ipDataValid       : in  sl;
      ipDataReady       : out sl;
      -- Interface to Ethernet frame block
      ethTxDataIn       : out slv(7 downto 0);
      ethTxDataValid    : out sl;
      ethTxDataLastByte : out sl;
      ethTxDataReady    : in  sl
   );
end IPv4Tx;

architecture rtl of IPv4Tx is

   type StateType is (IDLE_S, HEADER_PREP_0_S, HEADER_PREP_1_S, 
                      HEADER_PREP_2_S, HEADER_PREP_3_S,
                      HEADER_0_S, HEADER_1_S, HEADER_2_S, HEADER_3_S, HEADER_4_S,
                      PAYLOAD_S, PAUSE_S);
   
   type RegType is record
      state              : StateType;
      byteCount          : slv( 1 downto 0);
      header0            : slv(31 downto 0);
      header1            : slv(31 downto 0);
      header2            : slv(31 downto 0);
      header3            : slv(31 downto 0);
      header4            : slv(31 downto 0);
      header0Checksum    : slv(31 downto 0);
      header1Checksum    : slv(31 downto 0);
      header2Checksum    : slv(31 downto 0);
      header3Checksum    : slv(31 downto 0);
      header4Checksum    : slv(31 downto 0);
      ipCheckSum32       : slv(31 downto 0);
      ipCheckSum16       : slv(15 downto 0);
      wordsLeft          : slv(13 downto 0);
      data32             : slv(31 downto 0);
      data8              : slv( 7 downto 0);
      data8Valid         : sl;
      data8Last          : sl;
      ethTxDataIn        : slv(7 downto 0);
      ethTxDataValid     : sl;
      ethTxDataLast      : sl;
      ipDataReady        : sl;
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      state              => IDLE_S,
      byteCount          => (others => '1'),
      header0            => (others => '0'),
      header1            => (others => '0'),
      header2            => (others => '0'),
      header3            => (others => '0'),
      header4            => (others => '0'),
      header0Checksum    => (others => '0'),
      header1Checksum    => (others => '0'),
      header2Checksum    => (others => '0'),
      header3Checksum    => (others => '0'),
      header4Checksum    => (others => '0'),
      ipCheckSum32       => (others => '0'),
      ipChecksum16       => (others => '0'),
      wordsLeft          => (others => '0'),
      data32             => (others => '0'),
      data8              => (others => '0'),
      data8Valid         => '0',
      data8Last          => '0',
      ethTxDataIn        => (others => '0'),
      ethTxDataValid     => '0',
      ethTxDataLast      => '0',
      ipDataReady        => '0'
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
   
begin
      
   ----------------------------------
   -- State machine to prep packet --
   ----------------------------------
   comb : process(r,ethTxRst,ipPacketLength,ipPacketId,ipMoreFragments,
                  ipFragOffset,ipProtocol,ipSrcAddr,ipDstAddr,
                  ipData,ipDataValid,ethTxDataReady) is
      variable v : RegType;
   begin
      v := r;

      -- Set defaults / reset any pulsed signals
      v.data8Valid   := '0';
      v.data8Last    := '0';
      v.ipDataReady  := '0';

      -- State machine
      case(r.state) is 
         when IDLE_S =>
            v.byteCount  := (others => '1');
            if ipDataValid = '1' then
               -- Prepare header words
               v.header0         := IPV4_VERSION_C & IPV4_IHL_C & IPV4_DSCP_C & IPV4_ECN_C & ipPacketLength;
               v.header1         := ipPacketId & "00" & ipMoreFragments & ipFragOffset;
               v.header2         := IPV4_TTL_C & ipProtocol & x"0000"; --Placeholder for checksum
               v.header3         := ipSrcAddr(3) & ipSrcAddr(2) & ipSrcAddr(1) & ipSrcAddr(0);
               v.header4         := ipDstAddr(3) & ipDstAddr(2) & ipDstAddr(1) & ipDstAddr(0);
               -- Prepare initial checksum stages
               v.header0Checksum := conv_std_logic_vector(conv_integer(v.header0(31 downto 16)) + conv_integer(v.header0(15 downto 0)),32);
               v.header1Checksum := conv_std_logic_vector(conv_integer(v.header1(31 downto 16)) + conv_integer(v.header1(15 downto 0)),32);
               v.header2Checksum := conv_std_logic_vector(conv_integer(v.header2(31 downto 16)) + conv_integer(v.header2(15 downto 0)),32);
               v.header3Checksum := conv_std_logic_vector(conv_integer(v.header3(31 downto 16)) + conv_integer(v.header3(15 downto 0)),32);
               v.header4Checksum := conv_std_logic_vector(conv_integer(v.header4(31 downto 16)) + conv_integer(v.header4(15 downto 0)),32);
               -- Prep number of total payload words to read, not including header
               v.wordsLeft       := ipPacketLength(15 downto 2) - 5 - 1;
               -- Move to next state
               v.state           := HEADER_PREP_0_S;
            end if;
         when HEADER_PREP_0_S =>
            -- Partial addition of checksum
            v.ipChecksum32 := r.header0Checksum + r.header1Checksum + r.header2Checksum;
            v.state        := HEADER_PREP_1_S;
            -- Also go ahead and grab first word here and allow upstream block to clock to next word
            v.data32       := ipData;
            v.ipDataReady  := '1';
         when HEADER_PREP_1_S =>
            -- Remaining addition of checksum
            v.ipChecksum32 := r.ipChecksum32 + r.header3Checksum + r.header4Checksum;
            v.state        := HEADER_PREP_2_S;
         when HEADER_PREP_2_S =>
            -- Switch checksum to 16 bit version
            v.ipChecksum16 := conv_std_logic_vector(conv_integer(r.ipChecksum32(15 downto 0)) + conv_integer(r.ipChecksum32(31 downto 16)),16);
            v.state        := HEADER_PREP_3_S;
         when HEADER_PREP_3_S =>
            -- Bit flip of the checksum and place it into header
            v.header2(15 downto 0) := not(r.ipChecksum16);
            -- Move into actual data
            v.data8      := getByte(conv_integer(r.byteCount),r.header0);
            v.data8Valid := '1';
            v.state      := HEADER_0_S;
         when HEADER_0_S =>
            v.data8Valid := '1';
            if ethTxDataReady = '1'  and r.data8Valid = '1' then
               v.byteCount := r.byteCount - 1;
               v.data8 := getByte(conv_integer(v.byteCount),r.header0);
               if v.byteCount = 0 then
                  v.state     := HEADER_1_S;
               end if;
            end if;
         when HEADER_1_S =>
            v.data8Valid := '1';
            if ethTxDataReady = '1' and r.data8Valid = '1' then
               v.byteCount := r.byteCount - 1;
               v.data8     := getByte(conv_integer(v.byteCount),r.header1);
               if v.byteCount = 0 then
                  v.state     := HEADER_2_S;
               end if;
            end if;
         when HEADER_2_S =>
            v.data8Valid := '1';
            if ethTxDataReady = '1' and r.data8Valid = '1' then
               v.byteCount := r.byteCount - 1;
               v.data8     := getByte(conv_integer(v.byteCount),r.header2);
               if v.byteCount = 0 then
                  v.state     := HEADER_3_S;
               end if;
            end if;
         when HEADER_3_S =>
            v.data8Valid := '1';
            if ethTxDataReady = '1' and r.data8Valid = '1' then
               v.byteCount := r.byteCount - 1;
               v.data8     := getByte(conv_integer(v.byteCount),r.header3);
               if v.byteCount = 0 then
                  v.state     := HEADER_4_S;
               end if;
            end if;
         when HEADER_4_S =>
            v.data8Valid := '1';
            if ethTxDataReady = '1' and r.data8Valid = '1' then
               v.byteCount := r.byteCount - 1;
               v.data8     := getByte(conv_integer(v.byteCount),r.header4);
               if v.byteCount = 0 then
                  v.state       := PAYLOAD_S;
               end if;
            end if;
         when PAYLOAD_S =>
            v.data8Valid := '1';
            if ethTxDataReady = '1' and r.data8Valid = '1' then
               v.byteCount := r.byteCount - 1;
               v.data8     := getByte(conv_integer(v.byteCount),r.data32);
               if r.byteCount = 1 and r.wordsLeft /= 0 then
                  v.ipDataReady := '1';
               end if;
               if v.byteCount = 0 then
                  v.data32      := ipData;
                  if r.wordsLeft = 0 then
                     v.data8Last   := '1';
                     v.state       := PAUSE_S;
                  else
                     v.wordsLeft := r.wordsLeft - 1;
                  end if;
               end if;
            end if;
         when PAUSE_S =>
            v.data8Valid := '1';
            v.data8Last  := '1';
            if ethTxDataReady = '1' and r.data8Valid = '1' then
               v.data8Valid := '0';
               v.data8Last  := '0';
               v.state      := IDLE_S;
            end if;
--            -- Hold one extra cycle here to let the transfer finish
--            if r.data8Last = '0' then
--               v.state       := IDLE_S;
--            end if;
         when others =>
            v.state := IDLE_S;
      end case;
         
      -- Reset logic
      if (ethTxRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Outputs to ports
      ethTxDataIn       <= r.data8;
      ethTxDataValid    <= r.data8Valid;
      ethTxDataLastByte <= r.data8Last;
      ipDataReady       <= r.ipDataReady;
      
      -- Assign variable to signal
      rin <= v;

   end process;

   seq : process (ethTxClk) is
   begin
      if (rising_edge(ethTxClk)) then
         r <= rin after GATE_DELAY_G;
      end if;
   end process seq;   

end rtl;
