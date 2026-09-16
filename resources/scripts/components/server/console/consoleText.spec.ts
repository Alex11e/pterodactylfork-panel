import { consoleText } from './consoleText';

it('joins wrapped terminal lines without introducing artificial newlines', () => {
    const lines = [
        { isWrapped: false, translateToString: () => 'hello ' },
        { isWrapped: true, translateToString: () => 'world' },
        { isWrapped: false, translateToString: () => 'next line' },
    ];
    expect(consoleText({ length: lines.length, getLine: (i) => lines[i] })).toBe('hello world\nnext line');
});
it('handles an empty buffer and removes unused terminal rows', () => {
    expect(consoleText({ length: 0, getLine: () => undefined })).toBe('');
    expect(
        consoleText({
            length: 3,
            getLine: (i) => ({ isWrapped: false, translateToString: () => (i === 0 ? 'log' : '') }),
        })
    ).toBe('log');
});
