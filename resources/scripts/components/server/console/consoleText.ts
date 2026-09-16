interface BufferLine {
    isWrapped: boolean;
    translateToString(trimRight?: boolean): string;
}
interface ConsoleBuffer {
    length: number;
    getLine(index: number): BufferLine | undefined;
}

/** Export text only, without terminal escape sequences, joining display-wrapped lines. */
export function consoleText(buffer: ConsoleBuffer): string {
    let output = '';
    for (let index = 0; index < buffer.length; index++) {
        const line = buffer.getLine(index);
        if (line) output += (index > 0 && !line.isWrapped ? '\n' : '') + line.translateToString(true);
    }
    return output.trimEnd();
}
