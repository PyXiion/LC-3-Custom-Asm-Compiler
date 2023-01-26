module compiler;

import std.conv;
import parser;
import lexer;

short sign_extend(int x, int bitcount) {
  if ((x >> (bitcount - 1)) & 1) {
    x |= (0xFFFF << bitcount);
  }
  return x;
}

enum {
  OP_BR = 0,  // branch
  OP_ADD,     // add
  OP_LD,      // load
  OP_ST,      // store
  OP_JSR,     // jump register
  OP_AND,     // bitwise and
  OP_LDR,     // load register
  OP_STR,     // store register
  OP_RTI,     // unused
  OP_NOT,     // bitwise not
  OP_LDI,     // load indirect
  OP_STI,     // store indirect
  OP_JMP,     // jump
  OP_RES,     // reversed (unused)
  OP_LEA,     // load effective address
  OP_TRAP     // execute trap
}

class Compiler {
  private ushort[] code;
  private int pc;

  // BR, LD, LDI, LEA, ST, STI
  // replace 9 bits to PCoffset
  private string[int] pcoffsets9;
  // JSR
  // replace 11 bits
  private string[int] subroutines;

  private int[string] labels;

  this(Parser p) {
    parser = p;
  }

  ushort[] getCode() const {
    return code;
  }

  // ADD, AND
  private void addInstructionADD_AND(int instr, Reg r0, Reg r1, int imm5) {
    code ~= ((instr & 0xf) << 12) | ((r0 & 0x7) << 9) | ((r1 & 0x7) << 6) |
            (1 << 5) | (sign_extend(imm5, 5) & 0x1f);
    pc++;
  }
  // ADD, AND
  private void addInstructionADD_AND(int instr, Reg r0, Reg r1, Reg r2) {
    code ~= ((instr & 0xf) << 12) | ((r0 & 0x7) << 9) | ((r1 & 0x7) << 6) | (r2 & 0x7);
    pc++;
  }
  // BR
  private void addInstructionBR(string label, bool n, bool z, bool p) {
    // BR is 0000 opcode
    code ~= ((n & 1) << 11) | ((z & 1) << 10) | ((p & 1) << 9);
    branches[pc++] = label;
  }
  private void addInstructionJSR(string label) {
    code ~= ((OP_JSR & 0xf) << 12) | (1 << 11);
    subroutines[pc++] = label;
  }
  // JMP, JSRR
  private void addInstructionJMP_JSRR(int instr, Reg r0) {
    code ~= ((instr & 0xf) << 12) | ((r0 & 0x7) << 6);
    pc++;
  }
  private void addInstructionLD_LDI_LEA_ST_STI(int instr, Reg r0, string label) {
    code ~= ((instr & 0xf) << 12) | ((r0 & 0x7) << 9);
    pcoffsets9[pc++] = label;
  }
  private void addInstructionLDR_STR(int instr, Reg r0, Reg r1, int offset) {
    code ~= ((instr & 0xf) << 12) | ((r0 & 0x7) << 9) | ((r0 & 0x7) << 6) | (sign_extend(offset, 6) & 0x3f);
    pc++;
  }
  private void addInstructionNOT(Reg r0, Reg r1) {
    code ~= ((OP_NOT & 0xf) << 12) | ((r0 & 0x7) << 9) | ((r1 & 0x7) << 6) | 0x3f;
    pc++;
  }
  private void addInstructionRET() {
    addInstructionJMP_JSRR(OP_JMP, Reg.R7);
    pc++;
  }
  private void addInstructionRTI() {
    // unused
    // code ~= (OP_RTI & 0xf) << 12;
    // pc++;
  }
  private void addInstructionTRAP(int trap) {
    code ~= ((OP_TRAP & 0xf) << 12) | (trap & 0xff);
    pc++;
  }

  private TokenType getNodeChildKind(Node n, int index) {
    return n.children[index].kind;
  }
  private LexValue.ValType getNodeChildValueType(Node n, int index) {
    return n.children[index].value.type;
  }
  private void checkNodeChild(Node n, int index) {
    if (!(n.children.length > index))
      error("Argument required");
  }

  private Reg requireRegArg(Node n, ref int counter) {
    checkNodeChild(n, counter);
    Node child = n.children[counter++];
    if (child.kind == TokenType.ARG && child.value.type == LexValue.ValType.REGISTER) {
      return to!Reg(child.value.i);
    }
    error("Incorrect argument");
    assert(0);
  }
  private int requireIntArg(Node n, ref int counter) {
    checkNodeChild(n, counter);
    Node child = n.children[counter++];
    if (child.kind == TokenType.ARG && child.value.type == LexValue.ValType.INT) {
      return child.value.i;
    }
    error("Incorrect argument");
    assert(0);
  }

  private void error(string msg, Node n = null) {
    import core.stdc.stdlib;
    import std.format;
    // if (!n)
      writeln("Parser error: " ~ msg);
    // else
    // TODO
    exit(1);
  }

  void compile(Node node) {
    int childCounter;
    switch (node.kind) {
      case TokenType.ROOT:
        foreach (n; node.children) {
          compile(n);
        }
        break;
      case TokenType.ORG:
      case TokenType.INT:
        code ~= requireIntArg(node, childCounter);
        pc++;
        break;
      case TokenType.ADD:
      case TokenType.AND:
        int instr = OP_ADD ? node.kind == TokenType.ADD : OP_AND;
        Reg r0, r1;
        r0 = requireRegArg(node, childCounter);
        r1 = requireRegArg(node, childCounter);
        checkNodeChild(node, childCounter);
        if (getNodeChildValueType(node, childCounter) == LexValue.ValType.INT)
          addInstructionADD_AND(instr, r0, r1, requireIntArg(node, childCounter));
        else if (getNodeChildValueType(node, childCounter) == LexValue.ValType.REGISTER)
          addInstructionADD_AND(instr, r0, r1, requireRegArg(node, childCounter));
        else
          error("Incorrect argument. Register or decimal expected");
        break;  
      default:
        error("Unexpected token");
    }
  }
}