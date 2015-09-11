---------------------------------------------------------------------------------
-- Title         : UDP TX Fragmenter
-- Project       : General Purpose Core
---------------------------------------------------------------------------------
-- File          : UdpTxFragmenter.vhd
-- Author        : Kurtis Nishimura
---------------------------------------------------------------------------------
-- Description:
-- Connects UDP layer to IPv4 layer, decides how to fragment data into MTU-size 
-- blocks.
---------------------------------------------------------------------------------

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.GigabitEthPkg.all;

entity UdpTxFragmenter is 
   generic (
      GATE_DELAY_G : time    := 1 ns;
      MTU_SIZE_G   : integer := 1500;
      ID_OFFSET_G  : slv(15 downto 0) := (others => '0')
   );
   port ( 
      -- 125 MHz ethernet clock in
      ethTxClk          : in  sl;
      ethTxRst          : in  sl := '0';
      -- Header data
      ipPacketLength    : out slv(15 downto 0);
      ipPacketId        : out slv(15 downto 0);
      ipMoreFragments   : out sl;
      ipFragOffset      : out slv(12 downto 0);
      ipProtocol        : out slv( 7 downto 0);
      -- User data to be sent
      udpData           : in  slv(31 downto 0);
      udpDataValid      : in  sl;
      udpDataReady      : out sl;
      udpLength         : in  slv(15 downto 0);
      udpReq            : in  sl;
      udpAck            : out sl;
      -- Interface to IPv4 frame block
      ipData            : out slv(31 downto 0);
      ipDataValid       : out sl;
      ipDataReady       : in  sl
   );
end UdpTxFragmenter;

architecture rtl of UdpTxFragmenter is

   type StateType is (IDLE_S, CHECK_SIZE_S, 
                      SEND_MTU_PAUSE_S, SEND_MTU_S, 
                      SEND_REMAINDER_PAUSE_S, SEND_REMAINDER_S, 
                      WAIT_S);
   
   type RegType is record
      state           : StateType;
      udpBytesLeft    : slv(15 downto 0);
      mtuCount        : slv(15 downto 0);
      ipPacketLength  : slv(15 downto 0);
      ipPacketId      : slv(15 downto 0);
      ipMoreFragments : sl;
      ipFragOffset    : slv(12 downto 0);
      ipProtocol      : slv( 7 downto 0);
      udpAck          : sl;
      ipData          : slv(31 downto 0);
      ipDataValid     : sl;
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      state           => IDLE_S,
      udpBytesLeft    => (others => '0'),
      mtuCount        => (others => '0'),
      ipPacketLength  => (others => '0'),
      ipPacketId      => ID_OFFSET_G,
      ipMoreFragments => '0',
      ipFragOffset    => (others => '0'),
      ipProtocol      => (others => '0'),
      udpAck          => '0',
      ipData          => (others => '0'),
      ipDataValid     => '0'
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

   comb : process(r,ethTxRst,udpData,udpDataValid,udpLength,
                  udpReq,ipDataReady) is
      variable v : RegType;
   begin
      v := r;

      -- Set defaults / reset any pulsed signals
      udpDataReady <= '0';
      ipDataValid  <= '0';
      ipData       <= (others => '0');
      v.ipProtocol := UDP_PROTOCOL_C;
      
      -- State machine
      case(r.state) is 
         when IDLE_S =>
            if udpDataValid = '1' then
               v.udpBytesLeft := udpLength - 4;
               v.ipFragOffset := (others => '0');
               v.state        := CHECK_SIZE_S;
            end if;
         when CHECK_SIZE_S =>
            -- Wait for last transfer to finish
            if r.ipDataValid = '0' then
               -- If the size of the UDP payload + IPv4 header (20 bytes) is
               -- less than an MTU, then this is the only packet
               if conv_integer(r.udpBytesLeft) + 24 <= MTU_SIZE_G then
                  v.ipPacketLength  := r.udpBytesLeft + 24;
                  v.ipMoreFragments := '0';
                  v.state           := SEND_REMAINDER_PAUSE_S;
               else
                  v.ipPacketLength  := conv_std_logic_vector(MTU_SIZE_G,v.ipPacketLength'length);
                  v.ipMoreFragments := '1';
                  -- Offset here to stop on the right word
                  v.mtuCount        := conv_std_logic_vector(MTU_SIZE_G - 20 - 4,v.mtuCount'length);
                  v.state           := SEND_MTU_PAUSE_S;
               end if;
            end if;
         when SEND_MTU_PAUSE_S =>
            v.state := SEND_MTU_S;
         when SEND_MTU_S =>
            ipData       <= udpData;
            ipDataValid  <= udpDataValid;
            udpDataReady <= ipDataReady;
            if ipDataReady = '1' and udpDataValid = '1' then
               v.mtuCount     := r.mtuCount     - 4;
               v.udpBytesLeft := r.udpBytesLeft - 4;
               if r.mtuCount = 0 then
                  v.ipFragOffset := r.ipFragOffset + ( (MTU_SIZE_G-20)/8 );
                  v.state        := CHECK_SIZE_S;
               end if;
            end if;
         when SEND_REMAINDER_PAUSE_S =>
            v.state := SEND_REMAINDER_S;
         when SEND_REMAINDER_S =>
            ipData       <= udpData;
            ipDataValid  <= udpDataValid;
            udpDataReady <= ipDataReady;
            if ipDataReady = '1' and udpDataValid = '1' then
               v.udpBytesLeft := r.udpBytesLeft - 4;
               if r.udpBytesLeft = 0 then
                  v.udpAck := '1';
                  v.state  := WAIT_S;
               end if;
            end if;
         when WAIT_S => 
            if udpReq = '0' then
               v.ipPacketId := r.ipPacketId + 1;
               v.udpAck     := '0';
               v.state      := IDLE_S;
            end if;
         when others =>
            v.state := IDLE_S;
      end case;
         
      -- Reset logic
      if (ethTxRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Outputs to ports
      ipPacketLength  <= r.ipPacketLength;
      ipPacketId      <= r.ipPacketId;
      ipMoreFragments <= r.ipMoreFragments;
      ipFragOffset    <= r.ipFragOffset;
      ipProtocol      <= r.ipProtocol;
      udpAck          <= r.udpAck;
--      ipData          <= r.ipData;
--      ipDataValid     <= r.ipDataValid;
      
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
