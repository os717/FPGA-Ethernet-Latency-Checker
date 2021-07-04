/*
Modulo detector de cantos de subida

Hans Lehnert Merino
Universidad Técnica Federico Santa Maria
*/

module edge_detector(clk, in, out);
	parameter N = 1;

	input clk;
	input [N-1:0] in;
	output [N-1:0] out;

	reg [N-1:0] buffer = 0;

	assign out = in & ~buffer;

	always @(posedge clk)
		buffer <= in;
endmodule