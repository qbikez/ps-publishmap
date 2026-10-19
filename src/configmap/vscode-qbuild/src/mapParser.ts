export interface TextSpan {
  start: number;
  end: number;
}

export type MapValueKind = "hashtable" | "scriptblock" | "other";

export interface MapMember {
  key: string;
  keySpan: TextSpan;
  valueSpan: TextSpan;
  span: TextSpan;
  valueKind: MapValueKind;
  table?: MapTable;
  parent: MapTable;
}

export interface MapTable {
  span: TextSpan;
  contentSpan: TextSpan;
  members: MapMember[];
  parentMember?: MapMember;
}

export interface ParsedMap {
  text: string;
  tables: MapTable[];
  ignoredSpans: TextSpan[];
}

type TokenKind =
  | "word"
  | "string"
  | "hashOpen"
  | "leftBrace"
  | "rightBrace"
  | "leftParen"
  | "rightParen"
  | "leftBracket"
  | "rightBracket"
  | "equals"
  | "separator"
  | "other";

interface Token extends TextSpan {
  kind: TokenKind;
  value: string;
}

interface LexResult {
  tokens: Token[];
  ignoredSpans: TextSpan[];
}

const structuralCharacters = new Set([
  "{",
  "}",
  "(",
  ")",
  "[",
  "]",
  "=",
  ";",
  "'",
  '"',
  ",",
]);

function isNewLine(character: string): boolean {
  return character === "\r" || character === "\n";
}

function consumeNewLine(text: string, offset: number): number {
  return text[offset] === "\r" && text[offset + 1] === "\n"
    ? offset + 2
    : offset + 1;
}

function readQuotedString(text: string, start: number, quote: string): number {
  let offset = start + 1;
  while (offset < text.length) {
    if (text[offset] === "`") {
      offset += 2;
      continue;
    }
    if (text[offset] === quote) {
      if (text[offset + 1] === quote) {
        offset += 2;
        continue;
      }
      return offset + 1;
    }
    offset++;
  }
  return text.length;
}

function readHereString(text: string, start: number, quote: string): number {
  let offset = start + 2;
  if (!isNewLine(text[offset] ?? "")) {
    return start;
  }
  offset = consumeNewLine(text, offset);

  while (offset < text.length) {
    const lineStart = offset;
    while (offset < text.length && !isNewLine(text[offset])) {
      offset++;
    }
    const line = text.slice(lineStart, offset);
    if (line.trimStart().startsWith(`${quote}@`)) {
      return offset;
    }
    if (offset < text.length) {
      offset = consumeNewLine(text, offset);
    }
  }
  return text.length;
}

function lex(text: string): LexResult {
  const tokens: Token[] = [];
  const ignoredSpans: TextSpan[] = [];
  let offset = 0;

  const push = (kind: TokenKind, start: number, end: number): void => {
    tokens.push({ kind, start, end, value: text.slice(start, end) });
  };

  while (offset < text.length) {
    const character = text[offset];

    if (character === " " || character === "\t" || character === "\f") {
      offset++;
      continue;
    }

    if (isNewLine(character)) {
      const end = consumeNewLine(text, offset);
      push("separator", offset, end);
      offset = end;
      continue;
    }

    if (text.startsWith("<#", offset)) {
      const start = offset;
      const closing = text.indexOf("#>", offset + 2);
      offset = closing < 0 ? text.length : closing + 2;
      ignoredSpans.push({ start, end: offset });
      continue;
    }

    if (character === "#") {
      const start = offset;
      while (offset < text.length && !isNewLine(text[offset])) {
        offset++;
      }
      ignoredSpans.push({ start, end: offset });
      continue;
    }

    if (
      character === "@" &&
      (text[offset + 1] === "'" || text[offset + 1] === '"')
    ) {
      const end = readHereString(text, offset, text[offset + 1]);
      if (end !== offset) {
        push("string", offset, end);
        ignoredSpans.push({ start: offset, end });
        offset = end;
        continue;
      }
    }

    if (character === "'" || character === '"') {
      const end = readQuotedString(text, offset, character);
      push("string", offset, end);
      ignoredSpans.push({ start: offset + 1, end: Math.max(offset + 1, end - 1) });
      offset = end;
      continue;
    }

    if (text.startsWith("@{", offset)) {
      push("hashOpen", offset, offset + 2);
      offset += 2;
      continue;
    }

    const tokenKinds: Record<string, TokenKind> = {
      "{": "leftBrace",
      "}": "rightBrace",
      "(": "leftParen",
      ")": "rightParen",
      "[": "leftBracket",
      "]": "rightBracket",
      "=": "equals",
      ";": "separator",
      ",": "other",
    };
    const tokenKind = tokenKinds[character];
    if (tokenKind) {
      push(tokenKind, offset, offset + 1);
      offset++;
      continue;
    }

    const start = offset;
    while (
      offset < text.length &&
      !/\s/.test(text[offset]) &&
      !structuralCharacters.has(text[offset]) &&
      text[offset] !== "#"
    ) {
      offset++;
    }
    if (offset === start) {
      offset++;
    }
    push("word", start, offset);
  }

  return { tokens, ignoredSpans };
}

function normalizeKey(token: Token): string {
  if (token.kind !== "string") {
    return token.value;
  }

  const quoteOffset = token.value[0] === "@" ? 1 : 0;
  const quote = token.value[quoteOffset];
  const first = quoteOffset + 1;
  const last = token.value.endsWith(quote) ? token.value.length - 1 : token.value.length;
  return token.value
    .slice(first, last)
    .replaceAll(`${quote}${quote}`, quote)
    .replace(/`(.)/g, "$1");
}

function skipSeparators(tokens: Token[], index: number): number {
  while (tokens[index]?.kind === "separator") {
    index++;
  }
  return index;
}

function consumeBalanced(
  tokens: Token[],
  index: number,
  opening: TokenKind,
  closing: TokenKind,
): number {
  let depth = 0;
  while (index < tokens.length) {
    if (
      tokens[index].kind === opening ||
      (opening === "leftBrace" && tokens[index].kind === "hashOpen")
    ) {
      depth++;
    } else if (tokens[index].kind === closing) {
      depth--;
      if (depth === 0) {
        return index + 1;
      }
    }
    index++;
  }
  return tokens.length;
}

function consumeOtherValue(tokens: Token[], index: number): number {
  let braces = 0;
  let parentheses = 0;
  let brackets = 0;

  while (index < tokens.length) {
    const kind = tokens[index].kind;
    if (kind === "leftBrace") braces++;
    if (kind === "rightBrace") {
      if (braces === 0 && parentheses === 0 && brackets === 0) break;
      braces--;
    }
    if (kind === "leftParen") parentheses++;
    if (kind === "rightParen") parentheses--;
    if (kind === "leftBracket") brackets++;
    if (kind === "rightBracket") brackets--;
    if (
      kind === "separator" &&
      braces === 0 &&
      parentheses === 0 &&
      brackets === 0
    ) {
      break;
    }
    index++;
  }

  return index;
}

function findHashtableValueIndex(tokens: Token[], index: number): number | undefined {
  if (tokens[index]?.kind === "hashOpen") {
    return index;
  }
  if (
    tokens[index]?.kind === "leftBracket" &&
    tokens[index + 1]?.kind === "word" &&
    tokens[index + 1].value.toLowerCase() === "ordered" &&
    tokens[index + 2]?.kind === "rightBracket" &&
    tokens[index + 3]?.kind === "hashOpen"
  ) {
    return index + 3;
  }
  return undefined;
}

function parseTable(
  tokens: Token[],
  startIndex: number,
  textLength: number,
): { table: MapTable; nextIndex: number } {
  const opening = tokens[startIndex];
  const table: MapTable = {
    span: { start: opening.start, end: opening.end },
    contentSpan: { start: opening.end, end: opening.end },
    members: [],
  };
  let index = startIndex + 1;

  while (index < tokens.length) {
    index = skipSeparators(tokens, index);
    const token = tokens[index];
    if (!token) break;

    if (token.kind === "rightBrace") {
      table.contentSpan.end = token.start;
      table.span.end = token.end;
      return { table, nextIndex: index + 1 };
    }

    if (token.kind !== "word" && token.kind !== "string") {
      if (token.kind === "leftBrace") {
        index = consumeBalanced(tokens, index, "leftBrace", "rightBrace");
      } else {
        index++;
      }
      continue;
    }

    const keyToken = token;
    if (tokens[index + 1]?.kind !== "equals") {
      index = consumeOtherValue(tokens, index + 1);
      continue;
    }

    let valueIndex = skipSeparators(tokens, index + 2);
    const valueToken = tokens[valueIndex];
    const valueStart = valueToken?.start ?? tokens[index + 1].end;
    let valueEnd = valueStart;
    let nextIndex = valueIndex;
    let valueKind: MapValueKind = "other";
    let childTable: MapTable | undefined;
    const hashtableIndex = findHashtableValueIndex(tokens, valueIndex);

    if (hashtableIndex !== undefined) {
      const parsedChild = parseTable(tokens, hashtableIndex, textLength);
      childTable = parsedChild.table;
      valueKind = "hashtable";
      nextIndex = parsedChild.nextIndex;
      valueEnd = childTable.span.end;
    } else if (valueToken?.kind === "leftBrace") {
      valueKind = "scriptblock";
      nextIndex = consumeBalanced(tokens, valueIndex, "leftBrace", "rightBrace");
      valueEnd = tokens[nextIndex - 1]?.end ?? valueStart;
    } else {
      nextIndex = consumeOtherValue(tokens, valueIndex);
      valueEnd = tokens[nextIndex - 1]?.end ?? valueStart;
    }

    const member: MapMember = {
      key: normalizeKey(keyToken),
      keySpan: { start: keyToken.start, end: keyToken.end },
      valueSpan: { start: valueStart, end: valueEnd },
      span: { start: keyToken.start, end: valueEnd },
      valueKind,
      table: childTable,
      parent: table,
    };
    if (childTable) {
      childTable.parentMember = member;
    }
    table.members.push(member);
    index = nextIndex;
  }

  table.contentSpan.end = textLength;
  table.span.end = table.contentSpan.end;
  return { table, nextIndex: tokens.length };
}

export function parseMap(text: string): ParsedMap {
  const { tokens, ignoredSpans } = lex(text);
  const tables: MapTable[] = [];
  let index = 0;

  while (index < tokens.length) {
    if (tokens[index].kind === "hashOpen") {
      const parsed = parseTable(tokens, index, text.length);
      tables.push(parsed.table);
      index = parsed.nextIndex;
      continue;
    }
    if (tokens[index].kind === "leftBrace") {
      index = consumeBalanced(tokens, index, "leftBrace", "rightBrace");
      continue;
    }
    index++;
  }

  return { text, tables, ignoredSpans };
}

function findNestedTable(table: MapTable, offset: number): MapTable {
  for (const member of table.members) {
    if (
      member.table &&
      offset >= member.table.span.start &&
      offset <= member.table.span.end
    ) {
      return findNestedTable(member.table, offset);
    }
  }
  return table;
}

export function findTableAtOffset(
  parsed: ParsedMap,
  offset: number,
): MapTable | undefined {
  for (const table of parsed.tables) {
    if (offset >= table.span.start && offset <= table.span.end) {
      return findNestedTable(table, offset);
    }
  }
  return undefined;
}

export function isIgnoredOffset(parsed: ParsedMap, offset: number): boolean {
  return parsed.ignoredSpans.some(
    (span) => offset > span.start && offset < span.end,
  );
}
