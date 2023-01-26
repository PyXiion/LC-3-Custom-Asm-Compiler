module compiler;

import std.conv;
import parser;
import lexer;

// short sign_extend(int x, int bitcount) {
//   if ((x >> (bitcount - 1)) & 1) {
//     x |= (0xFFFF << bitcount);
//   }
//   return cast(ushort)x;
// }
int sign_extend(int x, int bitcount) {
  if (x < 0)
    x |= (1 << (bitcount - 1));
  else
    x &= ~(1 << (bitcount - 1));
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
  
  // ID for embed labels in macros and etc
  private int lastUniId;

  private string unify(string s) {
    import std.format;
    return format("%s_%X", s, lastUniId++);
  }

  // BR, LD, LDI, LEA, ST, STI
  // replace 9 bits to PCoffset
  private string[int] pcoffsets9;
  // JSR
  // replace 11 bits
  private string[int] subroutines;

  private int[string] labels;

  private Node[string] macros;

  const(ushort[]) getCode() const {
    return code;
  }

  private void addInstructionADD_AND(int instr, Reg r0, Reg r1, int imm5) {
    code ~= ((instr & 0xf) << 12) | ((r0 & 0x7) << 9) | ((r1 & 0x7) << 6) |
            (1 << 5) | (sign_extend(imm5, 5) & 0x1f);
    pc++;
  }
  private void addInstructionADD_AND(int instr, Reg r0, Reg r1, Reg r2) {
    code ~= ((instr & 0xf) << 12) | ((r0 & 0x7) << 9) | ((r1 & 0x7) << 6) | (r2 & 0x7);
    pc++;
  }
  private void addInstructionBR(string label, bool n, bool z, bool p) {
    // BR is 0000 opcode
    bool nzp = !n && !z && !p;
    n = n || nzp; z = z || nzp; p = p || nzp; // BR = BRnzp
    code ~= ((n & 1) << 11) | ((z & 1) << 10) | ((p & 1) << 9);
    pcoffsets9[pc++] = label;
  }
  private void addInstructionJSR(string label) {
    code ~= ((OP_JSR & 0xf) << 12) | (1 << 11);
    subroutines[pc++] = label;
  }
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
  private string requireLabelArg(Node n, ref int counter) {
    checkNodeChild(n, counter);
    Node child = n.children[counter++];
    if (child.kind == TokenType.ARG && child.value.type == LexValue.ValType.STRING) {
      return child.value.asStr;
    }
    error("Incorrect argument");
    assert(0);
  }

  private void error(string msg, Node n = null) {
    import core.stdc.stdlib;
    import std.stdio;
    import std.format;
    // if (!n)
      writeln("Compiler error: " ~ msg);
    // else
    // TODO
    exit(1);
  }

  void compile(Node node, bool _macro = false) {
    int childCounter;
    switch (node.kind) {
      // Instructions
      case TokenType.ROOT: {
        foreach (n; node.children) {
          compile(n);
        }
        if (_macro) break;
        foreach (i, label; pcoffsets9) {
          if (label in labels) {
            code[i] |= sign_extend(labels[label] - i, 9) & 0x1ff;
          }
          else
            error("Unknown label \"" ~ label ~ "\"");
        }
        foreach (i, label; subroutines) {
          if (label in labels) {
            code[i] |= sign_extend(labels[label] - i, 11) & 0x7ff;
          }
          else
            error("Unknown label \"" ~ label ~ "\"");
        }
        break;
      }
      case TokenType.MACRO_DEF: {
        if (!_macro)
          macros[requireLabelArg(node, childCounter)] = node;
        else {
          goto case TokenType.ROOT;
        }
        break;
      }
      case TokenType.INT:
      case TokenType.ORG: {
        pc++;
        int i = requireIntArg(node, childCounter);
        if (node.kind == TokenType.INT) code ~= cast(ushort)sign_extend(i, 16);
        else code ~= cast(ushort) i;
        break;
      }
      case TokenType.ADD:
      case TokenType.AND: {
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
      }
      case TokenType.BR: {
        addInstructionBR(requireLabelArg(node, childCounter), node.options.n, node.options.z, node.options.p);
        break;
      }
      case TokenType.JMP:
      case TokenType.JSRR: {
        int instr = OP_JMP ? node.kind == TokenType.JMP : OP_JSR;
        addInstructionJMP_JSRR(instr, requireRegArg(node, childCounter));
        break;
      }
      case TokenType.JSR: {
        addInstructionJSR(requireLabelArg(node, childCounter));
        break;
      }
      case TokenType.LD:
      case TokenType.LDI:
      case TokenType.LEA:
      case TokenType.ST:
      case TokenType.STI: {
        // some shit to get instr
        int instr;
        switch (node.kind) {
          case TokenType.LD: instr = OP_LD; break;
          case TokenType.LDI: instr = OP_LDI; break;
          case TokenType.LEA: instr = OP_LEA; break;
          case TokenType.ST: instr = OP_ST; break;
          case TokenType.STI: instr = OP_STI; break;
          default: assert(0);
        }
        addInstructionLD_LDI_LEA_ST_STI(instr, requireRegArg(node, childCounter), requireLabelArg(node, childCounter));
        break;
      }
      case TokenType.LDR:
      case TokenType.STR: {
        int instr = OP_LDR ? node.kind == TokenType.LDR : OP_STR;
        addInstructionLDR_STR(instr, requireRegArg(node, childCounter), requireRegArg(node, childCounter), 
                              requireIntArg(node, childCounter));
        break;
      }
      case TokenType.NOT: {
        addInstructionNOT(requireRegArg(node, childCounter), requireRegArg(node, childCounter));
        break;
      }
      case TokenType.RET: {
        addInstructionRET();
        break;
      }
      case TokenType.TRAP: {
        addInstructionTRAP(requireIntArg(node, childCounter));
        break;
      }
      // Directives
      case TokenType.BYTE: {
        code ~= sign_extend(requireIntArg(node, childCounter), 8) & 0xff;
        pc++;
        break;
      }
      case TokenType.LONG: {
        int i = requireIntArg(node, childCounter);
        code ~= (i >> 15) & 0xffff;
        code ~= i & 0xffff;
        break;
      }
      case TokenType.BLKW: {
        for (int i = requireIntArg(node, childCounter); i > 0; --i) {
          code ~= 0;
          pc++;
        }
        break;
      }
      case TokenType.ASCIZ:
      case TokenType.ASCII: {
        string s = requireLabelArg(node, childCounter);
        foreach (c; s) {
          code ~= cast(ushort) c;
          pc++;
        }
        if (node.kind == TokenType.ASCIZ) {
          code ~= 0;
          pc++;
        }
        break;
      }
      // Other
      case TokenType.ID: {
        string id = node.value.asStr;
        if (id in macros) {
          compile(macros[id], true);
        }
        else {
          // error("Unexpected identificator: " ~ id);
        }
        break;
      }
      case TokenType.LABEL: {
        string label = node.value.asStr;
        labels[label] = pc - 1; // magic number (There's something about offsetting and something else)
        break;
      }
      default:
        // error("Unexpected token");
    }
  }
}