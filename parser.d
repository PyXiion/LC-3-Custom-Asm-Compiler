module parser;

import std.stdio;
import std.string;
import std.conv;
import lexer;

enum TokenType {
  ROOT,
  ORG, INCLUDE, ASCII, ASCIZ, BYTE, INT, LONG, 

  LABEL, ID, 

  MACRO_DEF,
  
  // Instructions
  BR,         // branch
  ADD,        // add
  LD,         // load
  ST,         // store
  JSR,        // jump register
  AND,        // bitwise and
  LDR,        // load register
  STR,        // store register
  RTI,        // unused
  NOT,        // bitwise not
  LDI,        // load indirect
  STI,        // store indirect
  JMP,        // jump
  RES,        // reversed (unused)
  LEA,        // load effective address
  TRAP,        // execute trap
  RET,
  JSRR,

  ARG,
}

TokenType[LexKey] instrOneReg; // instructions like: instr r0
TokenType[LexKey] instrOneLab; // instructions like: instr label
TokenType[LexKey] instr1R1L; // instructions like: instr r0 label
TokenType[LexKey] directiveStr; // directives like: .dir "text"
TokenType[LexKey] directiveNum; // directives like: .dir 123

shared static this() {
  instrOneReg[LexKey.JMP] = TokenType.JMP;
  instrOneReg[LexKey.JSRR] = TokenType.JSRR;

  instrOneLab[LexKey.BR] = TokenType.BR;
  instrOneLab[LexKey.JSR] = TokenType.JSR;

  instr1R1L[LexKey.LD] = TokenType.LD;
  instr1R1L[LexKey.ST] = TokenType.ST;
  instr1R1L[LexKey.LDI] = TokenType.LDI;
  instr1R1L[LexKey.STI] = TokenType.STI;
  instr1R1L[LexKey.LEA] = TokenType.LEA;

  directiveStr[LexKey.ASCII] = TokenType.ASCII;
  directiveStr[LexKey.ASCIZ] = TokenType.ASCIZ;

  directiveNum[LexKey.BYTE] = TokenType.BYTE;
  directiveNum[LexKey.INT] = TokenType.INT;
  directiveNum[LexKey.LONG] = TokenType.LONG;
}

struct NodeOptions {
  bool n, z, p; // BR
  Reg[] regs;
}

class Node {
  TokenType kind;
  LexValue value;
  NodeOptions options;
  Node[] children;

  this(TokenType tt, LexValue val = LexValue(), NodeOptions opts = NodeOptions()) {
    kind = tt;
    value = val;
    options = opts;
  }

  template addArg( T )
  {
    void addArg(T arg) {
      Node n = new Node(TokenType.ARG);
      n.value.set(arg);
      children ~= n;
    }
  }
  template addArg( T : LexValue )
  {
    void addArg(T arg) {
      children ~= new Node(TokenType.ARG, arg);
    }
  }
}

class Parser {
  private Lexer lex;
  private Node root;

  this(Lexer lexer) {
    lex = lexer;
  }
  void error(string msg) {
    import core.stdc.stdlib;
    import std.format;
    writeln(format("Parser error at line %d, pos %d.\n" ~
                   "%s", lex.getLine, lex.getCur, msg));
    exit(1);
  }
  void setCode(string code) {
    lex.setCode(code);
  }

  void readComma() {
    if (lex.getSym != LexKey.COMMA) {
      error("Comma expected");
    }
    lex.next_token();
  }
  Reg parseReg() {
    if (lex.getSym == LexKey.IDENTIFICATOR) {
      string id = lex.getValue.asStr;
      if (id.length == 2 && (id[0] == 'r' || id[0] == 'R') && (id[1] >= '0' && id[1] <= '7')) {
        lex.next_token();
        return to!Reg(id[1] - '0');
      }
    }
    error("Register expected");
    assert(0);
  }
  int parseNum() {
    byte modifier = 1;
    if (lex.getSym == LexKey.PLUS)
      lex.next_token();
    else if (lex.getSym == LexKey.MINUS) {
      modifier = -1;
      lex.next_token();
    }
    if (lex.getSym == LexKey.NUM) {
      lex.next_token();
      return lex.getValue.i * modifier;
    }
    error("Number expected");
    assert(0);
  }

  Node statement(int depth=0) {
    Node n;
    // directives
    if (lex.getSym == LexKey.ORG) {
      n = new Node(TokenType.ORG);
      lex.next_token();
      n.addArg(parseNum);
    }
    else if (lex.getSym == LexKey.INCLUDE) {
      n = new Node(TokenType.INCLUDE);
      lex.next_token();
      if (lex.getSym == LexKey.STRING)
        n.addArg(lex.getValue.asStr);
      else {
        error("String expected");
      }
    }
    else if (lex.getSym in directiveStr) {
      lex.next_token();
      if (lex.getSym == LexKey.STRING) {
        n = new Node(directiveStr[lex.getSym]);
        n.addArg(lex.getValue);
        lex.next_token();
      }
      else {
        error("String expected");
      }
    }
    else if (lex.getSym in directiveNum) {
      lex.next_token();
      n = new Node(directiveNum[lex.getSym]);
      n.addArg(parseNum);
    }
    // macros
    else if (lex.getSym == LexKey.MACROSTART) {
      if (depth != 0) {
        error("Embedded macros not allowed");
      }
      n = new Node(TokenType.MACRO_DEF);
      lex.next_token();
      if (lex.getSym == LexKey.IDENTIFICATOR) {
        n.addArg(lex.getValue);
      }
      else {
        error("Macro's name expected");
      }
      lex.next_token();
      // TODO: args
      if (lex.getSym != LexKey.SEPARATOR) {
        error("End line expected");
      }
      lex.next_token();

      while (lex.getSym != LexKey.MACROEND) {
        n.children ~= statement(depth + 1);
        lex.next_token();
      }
      lex.next_token(); // skip MACROEND
    }
    // label
    else if (lex.getSym == LexKey.IDENTIFICATOR) {
      string id = lex.getValue.asStr;
      lex.next_token();
      if (lex.getSym != LexKey.COLON) {
        n = new Node(TokenType.ID);
        n.value.set(id);
      } 
      else {
        lex.next_token();
        n = new Node(TokenType.LABEL);
        n.value.set(id);
      }
    }
    // Instructions
    else if (lex.getSym == LexKey.ADD || lex.getSym == LexKey.AND) {
      n = new Node(lex.getSym == LexKey.ADD ? TokenType.ADD : TokenType.AND);
      lex.next_token();
      n.addArg(parseReg()); readComma();
      n.addArg(parseReg()); readComma();

      if (lex.getSym == LexKey.PLUS || lex.getSym == LexKey.MINUS ||
          lex.getSym == LexKey.NUM) {
        int imm5 = parseNum;
        if (imm5 < -16 || imm5 > 15) {
          error("ADD and AND instructions must have the imm5 in the range -16...15");
        }
        n.addArg(imm5);
      }
      else {
        n.options.regs ~= parseReg();
      }
    }
    else if (lex.getSym in instrOneReg) {
      n = new Node(instrOneReg[lex.getSym]);
      lex.next_token();
      n.addArg(parseReg);
    }
    else if (lex.getSym in instrOneLab) {
      n = new Node(instrOneLab[lex.getSym]);
      if (lex.getSym == LexKey.BR) {
        string id = lex.getValue.asStr;
        if (id.length > 2) {
          id = id[2..$];
          n.options.n = indexOf(id, 'n') != -1;
          n.options.z = indexOf(id, 'z') != -1;
          n.options.p = indexOf(id, 'p') != -1;
        }
      }
      lex.next_token();
      if (lex.getSym == LexKey.IDENTIFICATOR) {
        n.addArg(lex.getValue);
      }
      else {
        error("Label identificator expected");
      }
      lex.next_token();
    }
    else if (lex.getSym in instr1R1L) {
      n = new Node(instr1R1L[lex.getSym]);
      lex.next_token();
      n.addArg(parseReg); readComma;

      if (lex.getSym == LexKey.IDENTIFICATOR) {
        n.addArg(lex.getValue);
      }
      else {
        error("Label identificator expected");
      }
      lex.next_token();
    }
    else if (lex.getSym == LexKey.LDR) {
      n = new Node(TokenType.LDR);
      lex.next_token();
      n.addArg(parseReg); readComma;
      n.addArg(parseReg); readComma;
      n.addArg(parseNum);
    }
    else if (lex.getSym == LexKey.STR) {
      n = new Node(TokenType.STR);
      lex.next_token();
      n.addArg(parseReg); readComma;
      n.addArg(parseReg); readComma;
      n.addArg(parseNum);
    }
    else if (lex.getSym == LexKey.TRAP) {
      n = new Node(TokenType.TRAP);
      lex.next_token();
      n.addArg(parseNum);
    }
    else if (lex.getSym == LexKey.RET) {
      n = new Node(TokenType.RET);
      lex.next_token();
    }
    else if (lex.getSym == LexKey.NOT) {
      n = new Node(TokenType.NOT);
      lex.next_token();
      n.addArg(parseReg); readComma;
      n.addArg(parseReg);
    }
    else if (lex.getSym == LexKey.SEPARATOR) {
      lex.next_token();
      return null;
    }
    else {
      error("Invalid statement syntax");
    }
    return n;
  }

  Node parse() {
    lex.next_token(); // skip NONE
    root = new Node(TokenType.ROOT);

    do {
      Node n = statement;
      if (n) root.children ~= n;
    } while (lex.getSym != LexKey.EOF);
    
    return root;
  }
}