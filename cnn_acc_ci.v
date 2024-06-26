`include "timescale.vh"

module cnn_acc_ci (
    // Clock & Reset
    clk             ,
    reset_n         ,
    i_soft_reset    ,
    i_cnn_weight    ,
    i_in_valid      ,
    i_in_fmap       ,
    o_ot_valid      ,
    o_ot_ci_acc              
    );
`include "defines_cnn_core.vh"

localparam LATENCY = 1;
//==============================================================================
// Input/Output declaration
//==============================================================================
input                                       clk         	;
input                                       reset_n     	;
input                                       i_soft_reset	;
input     [ICH*KX*KY*DATA_LEN-1 : 0]        i_cnn_weight 	;
input                                       i_in_valid  	;
input     [ICH*IX*IY*DATA_LEN-1 : 0]        i_in_fmap    	;
output                                      o_ot_valid  	;
output    [OX*OY*DATA_LEN-1 : 0]  		    o_ot_ci_acc 	;

//==============================================================================
// Data Enable Signals 
//==============================================================================
wire    [LATENCY-1 : 0] 	ce;
reg     [LATENCY-1 : 0] 	r_valid;
reg    [ICH*OX*OY-1 : 0]   w_ot_valid;
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
// mul_acc kenel instance
//==============================================================================



// wire signed [DATA_LEN-1:0] parse_w_in_fmap_kernel[0:ICH-1][0:OY-1][0:OX-1][0:KY-1][0:KX-1];
/*
genvar ich, oy, ox;
genvar j;
generate
    for (ich = 0; ich < ICH; ich = ich+1) begin : gen_ich
        wire    [KX*KY*DATA_LEN-1 : 0]      w_cnn_weight    = i_cnn_weight[ich*KX*KY*DATA_LEN +: KX*KY*DATA_LEN];
        wire    [IX*IY*DATA_LEN-1 : 0]  	w_in_fmap    	= i_in_fmap[ich*IX*IY*DATA_LEN +: IX*IY*DATA_LEN];
        for (oy = 0; oy < OY; oy = oy+1) begin  : gen_oy
            for (ox = 0; ox < OX; ox = ox+1) begin : gen_ox
                // wire [KX*KY*DATA_LEN-1 : 0] w_in_fmap_kernel   = {w_in_fmap[((oy+0)*IX+ox)*DATA_LEN +: KX*DATA_LEN], w_in_fmap[((oy+1)*IX+ox)*DATA_LEN +: KX*DATA_LEN], w_in_fmap[((oy+2)*IX+ox)*DATA_LEN +: KX*DATA_LEN]};
                wire [KX*KY*DATA_LEN-1 : 0] w_in_fmap_kernel   = {w_in_fmap[((oy+2)*IX+ox)*DATA_LEN +: KX*DATA_LEN], w_in_fmap[((oy+1)*IX+ox)*DATA_LEN +: KX*DATA_LEN], w_in_fmap[((oy+0)*IX+ox)*DATA_LEN +: KX*DATA_LEN]};

                // for (j = 0; j<KX; j=j+1) begin : PARSE_W_FMAP_KERNEL
                //     assign parse_w_in_fmap_kernel[ich][oy][ox][0][j] = w_in_fmap_kernel[(KX*DATA_LEN * 0) + (DATA_LEN * j) +: DATA_LEN];
				// 	assign parse_w_in_fmap_kernel[ich][oy][ox][1][j] = w_in_fmap_kernel[(KX*DATA_LEN * 1) + (DATA_LEN * j) +: DATA_LEN];
				// 	assign parse_w_in_fmap_kernel[ich][oy][ox][2][j] = w_in_fmap_kernel[(KX*DATA_LEN * 2) + (DATA_LEN * j) +: DATA_LEN];
                // end

                assign	w_in_valid[ich*OY*OX + oy*OX + ox] = i_in_valid;

                cnn_kernel u_cnn_kernel(
                .clk             (clk            ),
                .reset_n         (reset_n        ),
                .i_soft_reset    (i_soft_reset   ),
                .i_cnn_weight    (w_cnn_weight   ),
                .i_in_valid      (w_in_valid[ich*OY*OX + oy*OX + ox]),
                .i_in_fmap       (w_in_fmap_kernel),
                .o_ot_valid      (w_ot_valid[ich*OY*OX + oy*OX + ox]),
                .o_ot_kernel_acc (w_ot_kernel_acc_temp)             
                );
            end
        end
    end
endgenerate
*/
//==============================================================================
// ci_acc = ci_acc + kernel_acc
//==============================================================================
//원래 있던거
reg    [ICH*OX*OY-1 : 0]               w_in_valid;
reg    [ICH*OX*OY*DATA_LEN-1 : 0]       w_ot_kernel_acc;


wire    [OX*OY*DATA_LEN-1 : 0]  		w_ot_ci_acc;
reg     [OX*OY*DATA_LEN-1 : 0]  		r_ot_ci_acc;
reg     [OX*OY*DATA_LEN-1 : 0]  		ot_ci_acc;

//내가 추가
//x state
parameter IDLE  = 4'b0000;
parameter x_0   = 4'b0001;
parameter x_0_l = 4'b0010;
parameter x_1   = 4'b0011;
parameter x_1_l = 4'b0100;
parameter x_2   = 4'b0101;
parameter x_2_l = 4'b0110;
parameter x_3   = 4'b0111;
parameter x_3_l = 4'b1000;
parameter x_4   = 4'b1001;
parameter x_4_l = 4'b1010; //A

//y, ich, done state
parameter y_st      = 4'b1011; //B
parameter ich_st    = 4'b1100; //C
parameter ich_1     = 4'b1101; //D
parameter ich_2     = 4'b1110; //E
parameter DONE      = 4'b1111; //F

//모든 reg
reg [3:0] present_state;
reg [3:0] next_state;

reg [KX*KY*DATA_LEN-1 : 0]      w_cnn_weight;  //  = i_cnn_weight[ich*KX*KY*DATA_LEN +: KX*KY*DATA_LEN];
reg [IX*IY*DATA_LEN-1 : 0]  	w_in_fmap;   
reg [KX*KY*DATA_LEN-1 : 0]      w_in_fmap_kernel;   //= {w_in_fmap[((oy+2)*IX+ox)*DATA_LEN +: KX*DATA_LEN], w_in_fmap[((oy+1)*IX+ox)*DATA_LEN +: KX*DATA_LEN], w_in_fmap[((oy+0)*IX+ox)*DATA_LEN +: KX*DATA_LEN]};
reg load;

reg [2:0] ox;
reg  oy;
reg [1:0] ich;

wire w_ot_valid_temp;
wire [DATA_LEN-1 : 0]       w_ot_kernel_acc_temp;


//initialize state
always @(posedge clk or negedge reset_n) begin
    if(!reset_n) present_state <= IDLE;
    else present_state <= next_state;
end

//determine next state
always @(*) begin
    case (present_state)
        IDLE: begin
            w_cnn_weight <= i_cnn_weight[0*KX*KY*DATA_LEN +: KX*KY*DATA_LEN];
            w_in_fmap <= i_in_fmap[0*IX*IY*DATA_LEN +: IX*IY*DATA_LEN];
            
            w_in_fmap_kernel <= 0;
            load <= 0;
            w_ot_valid <= 0;
            w_ot_kernel_acc <= 0;

            ox <= 0;
            oy <= 0;
            ich <= 0;

            if(!i_in_valid) next_state <= IDLE;
            else next_state <= x_0;
        end
       
        x_0: begin
            w_in_fmap_kernel[2*KX*DATA_LEN +: KX*DATA_LEN] <= w_in_fmap[((oy+2)*IX+ox)*DATA_LEN +: KX*DATA_LEN];
            w_in_fmap_kernel[1*KX*DATA_LEN +: KX*DATA_LEN] <= w_in_fmap[((oy+1)*IX+ox)*DATA_LEN +: KX*DATA_LEN];
            w_in_fmap_kernel[0*KX*DATA_LEN +: KX*DATA_LEN] <= w_in_fmap[((oy+0)*IX+ox)*DATA_LEN +: KX*DATA_LEN];
            load <= 1;
            next_state <= x_0_l;
        end
        
        x_0_l: begin
            load <= 0;                       
            if(!w_ot_valid_temp) next_state <= x_0_l;
            else begin
                //w_ot_valid[ich*OY*OX + oy*OX + ox] <= w_ot_valid_temp;
                w_ot_kernel_acc[(ich*OY*OX + oy*OX + ox)*DATA_LEN +: DATA_LEN] <= w_ot_kernel_acc_temp;
                
                next_state <= x_1_l;
            end

        end
 
        x_1_l: begin
            load <= 0;
            if(!w_ot_valid_temp) next_state <= x_1_l;
            else begin
                //w_ot_valid[ich*OY*OX + oy*OX + ox] <= w_ot_valid_temp;
                w_ot_kernel_acc[(ich*OY*OX + oy*OX + ox)*DATA_LEN +: DATA_LEN] <= w_ot_kernel_acc_temp;
                
                next_state <= x_0;
                ox <= 3'b010;
            end
        end
        x_2: begin
            w_in_fmap_kernel[2*KX*DATA_LEN +: KX*DATA_LEN] <= w_in_fmap[((oy+2)*IX+ox)*DATA_LEN +: KX*DATA_LEN];
            w_in_fmap_kernel[1*KX*DATA_LEN +: KX*DATA_LEN] <= w_in_fmap[((oy+1)*IX+ox)*DATA_LEN +: KX*DATA_LEN];
            w_in_fmap_kernel[0*KX*DATA_LEN +: KX*DATA_LEN] <= w_in_fmap[((oy+0)*IX+ox)*DATA_LEN +: KX*DATA_LEN];
            load <= 1;
            

            next_state <= x_2_l;
            
        end
        
        x_2_l: begin
            load <= 0;
            if(!w_ot_valid_temp) next_state <= x_2_l;
            else begin
                //w_ot_valid[ich*OY*OX + oy*OX + ox] <= w_ot_valid_temp;
                w_ot_kernel_acc[(ich*OY*OX + oy*OX + ox)*DATA_LEN +: DATA_LEN] <= w_ot_kernel_acc_temp;
                
                next_state <= x_0;
                ox <= 3'b011;
            end
        end
        x_3: begin
            w_in_fmap_kernel[2*KX*DATA_LEN +: KX*DATA_LEN] <= w_in_fmap[((oy+2)*IX+ox)*DATA_LEN +: KX*DATA_LEN];
            w_in_fmap_kernel[1*KX*DATA_LEN +: KX*DATA_LEN] <= w_in_fmap[((oy+1)*IX+ox)*DATA_LEN +: KX*DATA_LEN];
            w_in_fmap_kernel[0*KX*DATA_LEN +: KX*DATA_LEN] <= w_in_fmap[((oy+0)*IX+ox)*DATA_LEN +: KX*DATA_LEN];
            load <= 1;
            

            next_state <= x_3_l;
            
        end
        
        x_3_l: begin
            load <= 0;
            if(!w_ot_valid_temp) next_state <= x_3_l;
            else begin
                //w_ot_valid[ich*OY*OX + oy*OX + ox] <= w_ot_valid_temp;
                w_ot_kernel_acc[(ich*OY*OX + oy*OX + ox)*DATA_LEN +: DATA_LEN] <= w_ot_kernel_acc_temp;
                
                next_state <= x_0;
                ox <= 3'b100;
            end
        end
        x_4: begin
            w_in_fmap_kernel[2*KX*DATA_LEN +: KX*DATA_LEN] <= w_in_fmap[((oy+2)*IX+ox)*DATA_LEN +: KX*DATA_LEN];
            w_in_fmap_kernel[1*KX*DATA_LEN +: KX*DATA_LEN] <= w_in_fmap[((oy+1)*IX+ox)*DATA_LEN +: KX*DATA_LEN];
            w_in_fmap_kernel[0*KX*DATA_LEN +: KX*DATA_LEN] <= w_in_fmap[((oy+0)*IX+ox)*DATA_LEN +: KX*DATA_LEN];
            load <= 1;
            

            next_state <= x_4_l;
            
        end
        
        x_4_l: begin
            load <= 0;           
            if(!w_ot_valid_temp) next_state <= x_4_l;
            else if (oy == 0) begin 
                next_state <= y_st;
                //w_ot_valid[ich*OY*OX + oy*OX + ox] <= w_ot_valid_temp;
                w_ot_kernel_acc[(ich*OY*OX + oy*OX + ox)*DATA_LEN +: DATA_LEN] <= w_ot_kernel_acc_temp;
                //ox <= 3'b000;

            end
            else begin 
                next_state <= ich_st;
                //w_ot_valid[ich*OY*OX + oy*OX + ox] <= w_ot_valid_temp;
                w_ot_kernel_acc[(ich*OY*OX + oy*OX + ox)*DATA_LEN +: DATA_LEN] <= w_ot_kernel_acc_temp;
                //ox <= 3'b000;

            end
        end
        */
        y_st: begin
            if (oy == 0) begin
                oy <= 1'b1;
                next_state <= x_0;
                ox <= 3'b000;
            end
            else begin
                oy <= 0;
                next_state <= ich_st;
            end

        end
        
        ich_st: begin
            oy <= 0;
            ox <= 3'b000;
            if(ich == 0) next_state <= ich_1;
            else if (ich == 2'b01) next_state <= ich_2;
            else next_state <= DONE;
        end
        ich_1: begin
            ich <= 2'b01;
            w_cnn_weight <= i_cnn_weight[1*KX*KY*DATA_LEN +: KX*KY*DATA_LEN];
            w_in_fmap <= i_in_fmap[1*IX*IY*DATA_LEN +: IX*IY*DATA_LEN];
            next_state <= x_0;
        end
        ich_2: begin
            ich <= 2'b10;
            w_cnn_weight <= i_cnn_weight[2*KX*KY*DATA_LEN +: KX*KY*DATA_LEN];
            w_in_fmap <= i_in_fmap[2*IX*IY*DATA_LEN +: IX*IY*DATA_LEN];
            next_state <= x_0;
        end
        
        DONE: begin
            load <= 0;
            next_state <= IDLE;
            w_ot_valid <={32{1'b1}};

            w_cnn_weight <= 0;
            w_in_fmap <= 0;
        end
        
        default: begin
            w_cnn_weight <= i_cnn_weight[0*KX*KY*DATA_LEN +: KX*KY*DATA_LEN];
            w_in_fmap <= i_in_fmap[0*IX*IY*DATA_LEN +: IX*IY*DATA_LEN];
            
            w_in_fmap_kernel <= w_in_fmap_kernel;
            load <= 0;
            w_ot_valid <= 0;
            w_ot_kernel_acc <= 0;

            ox <= 0;
            oy <= 0;
            ich <= 0;

            next_state <= IDLE;
        end
    endcase
end


cnn_kernel u_cnn_kernel(
.clk             (clk            ),
.reset_n         (reset_n        ),
.i_soft_reset    (i_soft_reset   ),
.i_cnn_weight    (w_cnn_weight   ),
.i_in_valid      (load),
.i_in_fmap       (w_in_fmap_kernel),
.o_ot_valid      (w_ot_valid_temp),
.o_ot_kernel_acc (w_ot_kernel_acc_temp)             
);









// TODO Logic/ to accumulate the output of each Kernel
integer i;
always @(*) begin
	ot_ci_acc = {OX*OY*DATA_LEN{1'b0}};
    for(i = 0; i < ICH; i = i+1) begin
        ot_ci_acc = ot_ci_acc + w_ot_kernel_acc[i*OX*OY*DATA_LEN +: OX*OY*DATA_LEN];
    end
 
end
assign w_ot_ci_acc = ot_ci_acc;


// F/F
always @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
        r_ot_ci_acc[0 +: OX*OY*DATA_LEN] <= {OX*OY*DATA_LEN{1'b0}};
    end else if(i_soft_reset) begin
        r_ot_ci_acc[0 +: OX*OY*DATA_LEN] <= {OX*OY*DATA_LEN{1'b0}};
    end else if(&w_ot_valid)begin
        r_ot_ci_acc[0 +: OX*OY*DATA_LEN] <= w_ot_ci_acc[0 +: OX*OY*DATA_LEN];
    end
end

assign o_ot_valid = r_valid[LATENCY-1];
assign o_ot_ci_acc = r_ot_ci_acc;

endmodule
