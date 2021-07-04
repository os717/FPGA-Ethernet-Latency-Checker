/*
Generador de reloj

Hans Lehnert Merino
Universidad Técnica Federico Santa Maria
*/

module clk_gen(in_clk, out_clk);
	parameter SOURCE_CLK = 100000000;
	parameter TARGET_CLK = 1;
	parameter N = $clog2(SOURCE_CLK / TARGET_CLK);

	input in_clk;
	output reg out_clk;

	reg [N-1:0] count;

	always @(posedge in_clk) begin
		if (count < (SOURCE_CLK / TARGET_CLK) - 1) begin
			count <= count + 1'b1;
			out_clk <= 0;
		end
		else begin
			count <= 0;
			out_clk <= 1; //La salida se enciende por un único ciclo
		end
	end
endmodule