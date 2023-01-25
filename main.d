module main;

import std.stdio;
import std.string;
import std.file;
import std.getopt;
import std.conv;
import parser;
import lexer;

int main(string[] args)
{
    if (args.length < 2) {
        writeln("Usage: sasm <inputfile> [outputfile]");
        writeln("-h\tfor more information");
        return 0;
    }
    string arg1 = args[1];
    if (arg1 == "-h") {
        writeln("SASM - Simple Assembler for LC-3 by Savely Shulgin");
        writeln("-h\tShows help");
        return 0;
    }
    if (!exists(arg1)) {
        writeln("File \"" ~ arg1 ~ "\" doesn't exists");
        return 0;
    }
    if (!isFile(arg1)) {
        writeln("\"" ~ arg1 ~ "\" is not a file");
        return 0;
    }
    
    string code = readText(arg1);

    Lexer lex = new Lexer();
    lex.setCode(code);
    
    for (LexKey k = lex.next_token(); k != LexKey.EOF; k = lex.next_token()) {
        if (k == LexKey.SEPARATOR) writeln();
        else {
            LexValue val = lex.getValue;
            write("[" ~ to!string(k));
            if (val) {
                write(", \"" ~ val.asStr ~ "\"");
            }
            write("] ");
        }
    }
    writeln();
    writeln();

    Parser parser = new Parser(new Lexer);
    parser.setCode(code);
    Node n = parser.parse();

    void printNode(ref Node n, int depth = 0) {
        if (depth > 0) {
            for (int i = depth * 2 - 1; i >= 0; --i) {
                if (i == 0) write('-');
                else if (i == 1) write('+');
                else if (i % 2 == 0) write('|');
            }
        }
        write(to!string(n.kind));
        if (n.options.n) write('n');
        if (n.options.z) write('z');
        if (n.options.p) write('p');
        if (n.value || n.options.regs.length > 0) {
            write('(');
            bool semicolon = false;
            if (n.value) {
                write(n.value.asStr);
                semicolon = true;
            }
            if (n.options.regs.length > 0) {
                if (semicolon) write("; ");
                for (int i = 0; i < n.options.regs.length; ++i) {
                    write(to!string(n.options.regs[i]));
                    if (i + 1 != n.options.regs.length)
                        write(", ");
                }
            }
            write(')');
        }
        writeln();
        foreach (child; n.children)
            printNode(child, depth + 1);
    }

    printNode(n);
    
	return 0;
}
