`include "timescale.vh"

module cnn_core (
    // Clock & Reset
    clk             ,
    reset_n         ,
    i_soft_reset    ,
    i_cnn_weight    ,
    i_in_valid      ,
    i_in_fmap       ,
    o_ot_valid      ,
    o_ot_one_fmap
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
input     [ICH*IX*IY*DATA_LEN-1 : 0]        i_in_fmap    	;
output                                      o_ot_valid  	;
output    [OCH*OX*OY*DATA_LEN-1 : 0]        o_ot_one_fmap   ;

//==============================================================================
// Data Enable Signals 
//==============================================================================
wire    [LATENCY-1 : 0] 	ce;
reg     [LATENCY-1 : 0] 	r_valid;
wire    [OCH-1 : 0]         w_ot_valid;
reg     [OCH-1 : 0]         w_ot_valid_reg;
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
// acc ci instance
//==============================================================================

wire    [OCH-1 : 0]                     w_in_valid;
wire    [OCH*OX*OY*DATA_LEN-1 : 0]      w_ot_ci_acc;
reg     [OCH*OX*OY*DATA_LEN-1 : 0]      w_ot_ci_acc_reg;
wire    [OX*OY*DATA_LEN-1 : 0]          w_ot_ci_acc_temp;
// TODO Instantiation
// to call cnn_acc_ci instance. if use generate, you can use the template below.
/*
genvar ci_inst;
generate
	for(ci_inst = 0; ci_inst < OCH; ci_inst = ci_inst + 1) begin : gen_ci_inst
        
        assign	w_in_valid[ci_inst] = i_in_valid; 

        cnn_acc_ci u_cnn_acc_ci(
        .clk             (clk         ),
        .reset_n         (reset_n     ),
        .i_soft_reset    (i_soft_reset),
        .i_cnn_weight    (w_cnn_weight),
        .i_in_valid      (w_in_valid[ci_inst]),
        .i_in_fmap       (w_in_fmap),
        .o_ot_valid      (w_ot_valid[ci_inst]),
        .o_ot_ci_acc     (w_ot_ci_acc[ci_inst*OX*OY*(DATA_LEN) +: OX*OY*(DATA_LEN)])
        );
	end
endgenerate
*/

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

reg    [ICH*KX*KY*DATA_LEN-1 : 0]  w_cnn_weight; 	//= i_cnn_weight[ci_inst*ICH*KX*KY*DATA_LEN +: ICH*KX*KY*DATA_LEN];
reg    [ICH*IX*IY*DATA_LEN-1 : 0]  w_in_fmap;
//initialize state
always @(posedge clk or negedge reset_n) begin
    if(!reset_n) present_state <= st0;
    else present_state <= next_state;
end

//determine next state
always @(*) begin
    case (present_state)
        st0: begin
            load <= 0;
            w_in_fmap <= i_in_fmap[0 +: ICH*IX*IY*DATA_LEN];
            w_ot_ci_acc_reg <= 0;
            w_ot_valid_reg <= 0;
            w_cnn_weight <= 0;
            
            if(!i_in_valid) next_state <= st0;
            else            next_state <= st1;
        end 
        st1: begin
            load <= 1'b1;
            w_cnn_weight <= i_cnn_weight[0*ICH*KX*KY*DATA_LEN +: ICH*KX*KY*DATA_LEN];
            next_state <= st2;

            w_in_fmap <= w_in_fmap;
            w_ot_ci_acc_reg <= w_ot_ci_acc_reg;
            w_ot_valid_reg <= w_ot_valid_reg;
        end
        st2: begin
            load <= 0;
            if(!w_ot_valid_temp) next_state <= st2;
            else                 next_state <= st3;

            w_cnn_weight <= w_cnn_weight;
            w_in_fmap <= w_in_fmap;
            w_ot_ci_acc_reg <= w_ot_ci_acc_reg;
            w_ot_valid_reg <= w_ot_valid_reg;
        end     
        st3: begin
            load <= 1'b1;
            w_cnn_weight <= i_cnn_weight[1*ICH*KX*KY*DATA_LEN +: ICH*KX*KY*DATA_LEN];
            w_ot_ci_acc_reg[0*OX*OY*(DATA_LEN) +: OX*OY*(DATA_LEN)] <= w_ot_ci_acc_temp;
            w_ot_valid_reg <= 2'b01;
            next_state <= st4;

            w_in_fmap <= w_in_fmap;
        end
        st4: begin
            load <= 0;
            if(!w_ot_valid_temp) next_state <= st4;
            else                 next_state <= st5;

            w_cnn_weight <= w_cnn_weight;
            w_in_fmap <= w_in_fmap;
            w_ot_ci_acc_reg <= w_ot_ci_acc_reg;
            w_ot_valid_reg <= w_ot_valid_reg;
        end    
        st5: begin
            load <= 0;
            w_ot_valid_reg <= 2'b11;
            w_ot_ci_acc_reg[1*OX*OY*(DATA_LEN) +: OX*OY*(DATA_LEN)] <= w_ot_ci_acc_temp;
            next_state <= st0;
            w_in_fmap <= w_in_fmap;
            w_cnn_weight <= w_cnn_weight;
        end
        default: begin 
            load <= 0;
            w_cnn_weight <= 0;
            w_ot_ci_acc_reg <= 0;
            w_ot_valid_reg <= 0;
            next_state <= 0;
            w_in_fmap <= 0;
        end

    endcase
end

assign w_ot_ci_acc = w_ot_ci_acc_reg;
assign w_ot_valid = w_ot_valid_reg;

//instantiation
cnn_acc_ci u_cnn_acc_ci(
.clk             (clk         ),
.reset_n         (reset_n     ),
.i_soft_reset    (i_soft_reset),
.i_cnn_weight    (w_cnn_weight),
.i_in_valid      (load),
.i_in_fmap       (w_in_fmap),
.o_ot_valid      (w_ot_valid_temp),
.o_ot_ci_acc     (w_ot_ci_acc_temp)
);
// w_ot_ci_acc[ci_inst*OX*OY*(DATA_LEN) +: OX*OY*(DATA_LEN)]]

reg         [OCH*OX*OY*DATA_LEN-1 : 0]  r_ot_ci_acc;

always @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
        r_ot_ci_acc <= 0;
    end else if(i_soft_reset) begin
        r_ot_ci_acc <= 0;
    end else if(&w_ot_valid) begin
        r_ot_ci_acc <= w_ot_ci_acc;
    end
end

//==============================================================================
// No Activation
//==============================================================================
assign o_ot_valid = r_valid[LATENCY-1];
assign o_ot_one_fmap  = r_ot_ci_acc;

endmodule

