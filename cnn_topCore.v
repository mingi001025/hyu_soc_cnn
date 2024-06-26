`include "timescale.vh"

module cnn_topCore (
    // Clock & Reset
    clk             ,
    reset_n         ,
    i_soft_reset    ,
    i_cnn_weight    ,
    i_in_valid      ,
    i_in_fmap       ,
    o_ot_valid      ,
    o_ot_fmap             
    );
`include "defines_cnn_core.vh"

localparam LATENCY = 1;
//==============================================================================
// Input/Output declaration
//==============================================================================
input                                       clk         	;
input                                       reset_n     	;
input                                       i_soft_reset	;
input     [OCH*ICH*KX*KY*DATA_LEN-1 : 0]    i_cnn_weight 	;
input                                       i_in_valid  	;
input     [IN*ICH*IX*IY*DATA_LEN-1 : 0]     i_in_fmap    	;
output                                      o_ot_valid  	;
output    [IN*OCH*OX*OY*DATA_LEN-1 : 0]     o_ot_fmap    	;

//==============================================================================
// Data Enable Signals 
//==============================================================================
wire    [LATENCY-1 : 0] 	ce;
reg     [LATENCY-1 : 0] 	r_valid;
wire    [IN-1 : 0]          w_ot_valid;
reg     [IN-1 : 0]          w_ot_valid_reg;
wire                        w_ot_valid_temp;


always @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
        r_valid   <= {LATENCY{1'b0}};
    end else if(i_soft_reset) begin
        r_valid   <= {LATENCY{1'b0}};
    end else begin
        r_valid[LATENCY-1]  <= &w_ot_valid;
    end
end

assign	ce = r_valid;

//==============================================================================
// cnn core instance for stride
//==============================================================================

wire    [IN-1 : 0]                      w_in_valid;
wire    [IN*OCH*OX*OY*DATA_LEN-1 : 0]   w_ot_one_fmap;
reg     [IN*OCH*OX*OY*DATA_LEN-1 : 0]   w_ot_one_fmap_reg;
wire    [OCH*OX*OY*DATA_LEN-1 : 0]      w_ot_one_fmap_temp;
// TODO Instantiation
// to call cnn_acc_ci instance. if use generate, you can use the template below.
reg    [OCH*ICH*KX*KY*DATA_LEN-1 : 0]  w_cnn_weight; 
reg    [ICH*IX*IY*DATA_LEN-1 : 0]  w_in_fmap;


//FSM
parameter st0 = 3'b000;
parameter st1 = 3'b001;
parameter st2 = 3'b010;
parameter st3 = 3'b011;
parameter st4 = 3'b100;
parameter st5 = 3'b101;

reg [2:0] present_state;
reg [2:0] next_state;
reg       load;
//initialize state
always @(posedge clk or negedge reset_n ) begin
    if(!reset_n) present_state <= st0;
    else present_state <= next_state;
end

//determine next state
always @(*) begin
    case (present_state)
        st0: begin 
            load <= 0;
            w_cnn_weight <= i_cnn_weight[0 +: OCH*ICH*KX*KY*DATA_LEN];
            w_ot_one_fmap_reg <= 0;
            w_ot_valid_reg <= 0;
            w_in_fmap <= 0;
            if(!i_in_valid) next_state <= st0;
            else next_state <= st1;
        end
        st1: begin
            load <= 1'b1;
            w_in_fmap <= i_in_fmap[0*ICH*IX*IY*DATA_LEN +: ICH*IX*IY*DATA_LEN];
            next_state <= st2;

            w_cnn_weight <= w_cnn_weight;
            w_ot_one_fmap_reg <= w_ot_one_fmap_reg;
            w_ot_valid_reg <= w_ot_valid_reg;

        end
        st2: begin
            load <= 0;
            if(!w_ot_valid_temp) next_state <= st2;
            else next_state <= st3;

            w_cnn_weight <= w_cnn_weight;
            w_ot_one_fmap_reg <= w_ot_one_fmap_reg;
            w_ot_valid_reg <= w_ot_valid_reg;
            w_in_fmap <= w_in_fmap;
        end
        st3: begin
            load <= 1'b1; 
            w_in_fmap <= i_in_fmap[1*ICH*IX*IY*DATA_LEN +: ICH*IX*IY*DATA_LEN];           
            w_ot_one_fmap_reg[0*OCH*OX*OY*DATA_LEN +: OCH*OX*OY*DATA_LEN] = w_ot_one_fmap_temp;
            w_ot_valid_reg <= 2'b01;
            next_state <= st4;

            w_cnn_weight <= w_cnn_weight;
        end
        st4: begin
            load <= 0;
            if(!w_ot_valid_temp) next_state <= st4;
            else next_state <= st5;

            w_cnn_weight <= w_cnn_weight;
            w_ot_one_fmap_reg <= w_ot_one_fmap_reg;
            w_ot_valid_reg <= w_ot_valid_reg;
            w_in_fmap <= w_in_fmap;

        end
        st5: begin
            load <= 0;
            w_ot_valid_reg <= 2'b11;
            w_ot_one_fmap_reg[1*OCH*OX*OY*DATA_LEN +: OCH*OX*OY*DATA_LEN] = w_ot_one_fmap_temp;
            w_cnn_weight <= w_cnn_weight;
            w_in_fmap <= w_in_fmap;
            next_state <= st0;
        end
        
        default: begin
            load <= 0;
            w_cnn_weight <= 0;
            w_ot_one_fmap_reg <= 0;
            w_ot_valid_reg <= 0;
            next_state <= 0;
            w_in_fmap <= 0;
        end
    endcase
end


reg     [IN*OCH*OX*OY*DATA_LEN-1 : 0]   r_ot_one_fmap;

always @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin  
        r_ot_one_fmap <= 0;
    end else if(i_soft_reset) begin
        r_ot_one_fmap <= 0;
    end else if(&w_ot_valid) begin
        r_ot_one_fmap <= w_ot_one_fmap;
    end
end

assign w_ot_one_fmap = w_ot_one_fmap_reg;
assign w_ot_valid = w_ot_valid_reg;

// instantiation block
cnn_core u_cnn_core(
.clk             (clk         ),
.reset_n         (reset_n     ),
.i_soft_reset    (i_soft_reset),
.i_cnn_weight    (w_cnn_weight),
.i_in_valid      (load),
.i_in_fmap       (w_in_fmap),
.o_ot_valid      (w_ot_valid_temp),
.o_ot_one_fmap   (w_ot_one_fmap_temp)
);


//==============================================================================
// No Activation
//==============================================================================
assign o_ot_valid = r_valid[LATENCY-1];
assign o_ot_fmap  = r_ot_one_fmap;

endmodule

