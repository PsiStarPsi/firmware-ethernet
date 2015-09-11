---------------------------------------------------------------------------------
-- Title         : Arbiter between multiple IP interfaces
-- Project       : General Purpose Core
---------------------------------------------------------------------------------
-- File          : IpV4Arbiter.vhd
-- Author        : Kurtis Nishimura
---------------------------------------------------------------------------------
-- Description:
-- Cycles through channels.
---------------------------------------------------------------------------------

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.GigabitEthPkg.all;

entity IpV4Arbiter is 
   generic (
      NUM_IP_G     : integer := 1;
      GATE_DELAY_G : time := 1 ns
   );
   port ( 
      -- 125 MHz ethernet clock in
      ethTxClk             : in  sl;
      ethTxRst             : in  sl;
      -- Multiple data inputs 
      multIpTxDataIn       : in  Word8Array(NUM_IP_G-1 downto 0);
      multIpTxDataValid    : in  slv(NUM_IP_G-1 downto 0);
      multIpTxDataLastByte : in  slv(NUM_IP_G-1 downto 0);
      multIpTxDataReady    : out slv(NUM_IP_G-1 downto 0);
      -- MUXed data out
      ipTxData             : out slv(7 downto 0);
      ipTxDataValid        : out sl;
      ipTxDataLastByte     : out sl;
      ipTxDataReady        : in  sl
   );
end IpV4Arbiter;

architecture rtl of IpV4Arbiter is

   type StateType is (IDLE_S, PACKET_S);
   
   type RegType is record
      state             : StateType;
      channel           : slv(3 downto 0);
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      state             => IDLE_S,
      channel           => (others => '0')
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
   
   signal fifoWrData      : slv(7 downto 0) := (others => '0');
   signal fifoWrDataValid : sl := '0';
   signal fifoWrDataLast  : sl := '0';
   signal fifoWrDataReady : sl := '0';
   
   
begin

   ---------------------------
   -- Small buffering FIFO ---
   ---------------------------
   U_FifoDist8x16 : entity work.fifoDist8x16
      port map (
        s_aclk        => ethTxClk,
        s_aresetn     => not(ethTxRst),
        s_axis_tvalid => fifoWrDataValid,
        s_axis_tready => fifoWrDataReady,
        s_axis_tdata  => fifoWrData,
        s_axis_tlast  => fifoWrDataLast,
        m_axis_tvalid => ipTxDataValid,
        m_axis_tready => ipTxDataReady,
        m_axis_tdata  => ipTxData,
        m_axis_tlast  => ipTxDataLastByte
     );

   ---------------------------
   -- MUX the input data   ---
   ---------------------------
   mux : process(r,multIpTxDataIn,multIpTxDataValid,multIpTxDataLastByte,fifoWrDataReady) begin
      fifoWrDataValid <= multIpTxDataValid(conv_integer(r.channel));
      fifoWrData      <= multIpTxDataIn(conv_integer(r.channel));
      fifoWrDataLast  <= multIpTxDataLastByte(conv_integer(r.channel));
      for i in 0 to NUM_IP_G-1 loop
         if i = conv_integer(r.channel) then
            multIpTxDataReady(i) <= fifoWrDataReady;
         else
            multIpTxDataReady(i) <= '0';
         end if;
      end loop;
   end process mux;
   
   
   comb : process(r,ethTxRst,multIpTxDataIn,multIpTxDataValid,
                  multIpTxDataLastByte,ipTxDataReady,
                  fifoWrDataValid,fifoWrDataLast,fifoWrDataReady) is
      variable v : RegType;
   begin
      v := r;

      -- Set defaults / reset any pulsed signals
      
      -- State machine
      case(r.state) is 
         when IDLE_S =>
            if multIpTxDataValid(conv_integer(r.channel)) = '1' then
               v.state := PACKET_S;
            else 
               if r.channel < NUM_IP_G-1 then
                  v.channel := r.channel + 1;
               else
                  v.channel := (others => '0');
               end if;
            end if;
         when PACKET_S =>
            if (fifoWrDataValid = '1' and
                fifoWrDataLast  = '1' and
                fifoWrDataReady = '1') then
               if r.channel < NUM_IP_G-1 then
                  v.channel := r.channel + 1;
               else
                  v.channel := (others => '0');
               end if;               
               v.state := IDLE_S;
            end if;
         when others =>
            v.state := IDLE_S;
      end case;
         
      -- Reset logic
      if (ethTxRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Outputs to ports
         
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
