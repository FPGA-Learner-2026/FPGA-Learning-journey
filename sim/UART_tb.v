`timescale 1ns/1ns

module UART_tb();
    reg CLK,RESET_N;
    reg [7:0] SW;
    wire TX,LED;
    UART uart1(
        .CLK(CLK),
        .RESET_N(RESET_N),
        .SW(SW),
        .TX(TX),
        .LED(LED)
    );

    initial SW = 8'b0000_0000;
    
    initial CLK = 1;
    always #10 CLK = ~CLK;

    initial begin
        RESET_N = 0;
        #201 RESET_N = 1;SW = 8'b1010_0101;
        #1_000_000_001 SW = 8'b1011_0001;
        #1_500_000_000  $stop;
    end

endmodule
