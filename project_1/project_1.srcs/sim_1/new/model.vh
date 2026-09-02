function automatic integer rand_range;
    input integer lo;
    input integer hi;
    reg [31:0] draw;
    begin
        draw = $random(rnd_seed);
        rand_range = lo + (draw % (hi - lo + 1));
    end
endfunction
task automatic alu_model;
    input  signed [NB_DATA-1:0] a;
    input  signed [NB_DATA-1:0] b;
    input         [NB_OP-1:0]   op;
    output signed [NB_DATA-1:0] data;
    output                      zero;
    output                      ovf;
    reg [NB_DATA:0] ext; 
    begin
        ovf  = 1'b0;
        data = {NB_DATA{1'b0}};
        case (op)
            OP_ADD: begin
                ext  = a + b;
                data = ext[NB_DATA-1:0];
                ovf  = (a[NB_DATA-1] == b[NB_DATA-1]) &&
                       (data[NB_DATA-1] != a[NB_DATA-1]);
            end
            OP_SUB: begin
                ext  = a - b;
                data = ext[NB_DATA-1:0];
                ovf  = (a[NB_DATA-1] != b[NB_DATA-1]) &&
                       (data[NB_DATA-1] != a[NB_DATA-1]);
            end
            OP_AND:  data = a & b;
            OP_OR :  data = a | b;
            OP_XOR:  data = a ^ b;
            OP_SRA:  data = a >>> b;
            OP_SRL:  data = a >> b;
            OP_NOR:  data = ~(a | b);
            default: data = {NB_DATA{1'b0}};
        endcase
        zero = (data == {NB_DATA{1'b0}});
    end
endtask
                       