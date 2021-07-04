/*
Contador simple
*/

module counter(
	input clk,
	input rst,

	input enable,

	output reg [WIDTH-1:0] count
	);
	
	parameter WIDTH = 32;

	always @(posedge clk or posedge rst) begin
		if (rst) begin
			count <= 0;
		end
		else if (enable) begin
			count <= count + 1'b1;
		end
	end

endmodule