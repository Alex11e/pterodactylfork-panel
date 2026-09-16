import React, { useEffect, useMemo, useRef, useState } from 'react';
import { ITerminalOptions, Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import { SearchAddon } from 'xterm-addon-search';
import { SearchBarAddon } from 'xterm-addon-search-bar';
import { WebLinksAddon } from 'xterm-addon-web-links';
import { Unicode11Addon } from 'xterm-addon-unicode11';
import { ScrollDownHelperAddon } from '@/plugins/XtermScrollDownHelperAddon';
import SpinnerOverlay from '@/components/elements/SpinnerOverlay';
import { ServerContext } from '@/state/server';
import { usePermissions } from '@/plugins/usePermissions';
import { theme as th } from 'twin.macro';
import useEventListener from '@/plugins/useEventListener';
import { debounce } from 'debounce';
import { usePersistedState } from '@/plugins/usePersistedState';
import { SocketEvent, SocketRequest } from '@/components/server/events';
import classNames from 'classnames';
import { ChevronDoubleRightIcon } from '@heroicons/react/solid';

import 'xterm/css/xterm.css';
import styles from './style.module.css';
import usePanelText from '@/plugins/usePanelText';
import { consoleText } from './consoleText';

const theme = {
    background: th`colors.black`.toString(),
    cursor: 'transparent',
    black: th`colors.black`.toString(),
    red: '#E54B4B',
    green: '#9ECE58',
    yellow: '#FAED70',
    blue: '#396FE2',
    magenta: '#BB80B3',
    cyan: '#2DDAFD',
    white: '#d0d0d0',
    brightBlack: 'rgba(255, 255, 255, 0.2)',
    brightRed: '#FF5370',
    brightGreen: '#C3E88D',
    brightYellow: '#FFCB6B',
    brightBlue: '#82AAFF',
    brightMagenta: '#C792EA',
    brightCyan: '#89DDFF',
    brightWhite: '#ffffff',
    selection: '#FAF089',
};

const terminalProps: ITerminalOptions = {
    disableStdin: true,
    cursorStyle: 'underline',
    allowTransparency: true,
    fontSize: 12,
    fontFamily: th('fontFamily.mono'),
    rows: 30,
    scrollback: 5000,
    theme: theme,
};

export default () => {
    const text = usePanelText();
    const TERMINAL_PRELUDE = '\u001b[1m\u001b[33mcontainer@pterodactyl~ \u001b[0m';
    const ref = useRef<HTMLDivElement>(null);
    const terminal = useMemo(() => new Terminal({ ...terminalProps }), []);
    const fitAddon = useMemo(() => new FitAddon(), []);
    const searchAddon = useMemo(() => new SearchAddon(), []);
    const searchBar = useMemo(() => new SearchBarAddon({ searchAddon }), [searchAddon]);
    const webLinksAddon = useMemo(() => new WebLinksAddon(), []);
    const unicode11Addon = useMemo(() => new Unicode11Addon(), []);
    const scrollDownHelperAddon = useMemo(() => new ScrollDownHelperAddon(), []);
    const [query, setQuery] = useState('');
    const [notice, setNotice] = useState('');
    const [fontSize, setFontSize] = useState(12);
    const [follow, setFollow] = useState(true);
    const followRef = useRef(true);
    const { connected, instance } = ServerContext.useStoreState((state) => state.socket);
    const [canSendCommands] = usePermissions(['control.console']);
    const serverId = ServerContext.useStoreState((state) => state.server.data!.id);
    const isTransferring = ServerContext.useStoreState((state) => state.server.data!.isTransferring);
    const [history, setHistory] = usePersistedState<string[]>(`${serverId}:command_history`, []);
    const [historyIndex, setHistoryIndex] = useState(-1);
    // SearchBarAddon has hardcoded z-index: 999 :(
    const zIndex = `
    .xterm-search-bar__addon {
        z-index: 10;
    }`;

    const handleConsoleOutput = (line: string, prelude = false) => {
        const position = terminal.buffer.active.viewportY;
        terminal.writeln(
            (prelude ? TERMINAL_PRELUDE : '') + line.replace(/(?:\r\n|\r|\n)$/im, '') + '\u001b[0m',
            () => {
                if (!followRef.current) terminal.scrollToLine(position);
            }
        );
    };

    const search = (previous = false) => {
        if (!query || !terminal.element) return;
        const found = previous ? searchAddon.findPrevious(query) : searchAddon.findNext(query);
        setNotice(found ? 'Match found.' : 'No match found.');
    };
    const downloadLog = () => {
        const url = URL.createObjectURL(
            new Blob([consoleText(terminal.buffer.active)], { type: 'text/plain;charset=utf-8' })
        );
        const link = document.createElement('a');
        link.href = url;
        link.download = `console-${serverId}-${new Date().toISOString().replace(/[:.]/g, '-')}.txt`;
        link.click();
        window.setTimeout(() => URL.revokeObjectURL(url), 1000);
    };

    useEffect(() => {
        terminal.options.fontSize = fontSize;
        if (terminal.element) fitAddon.fit();
    }, [fontSize, terminal, fitAddon]);
    useEffect(() => () => terminal.dispose(), [terminal]);

    const handleTransferStatus = (status: string) => {
        switch (status) {
            // Sent by either the source or target node if a failure occurs.
            case 'failure':
                handleConsoleOutput(text('Transfer has failed.'), true);
                return;
        }
    };

    const handleDaemonErrorOutput = (line: string) =>
        terminal.writeln(
            TERMINAL_PRELUDE + '\u001b[1m\u001b[41m' + line.replace(/(?:\r\n|\r|\n)$/im, '') + '\u001b[0m'
        );

    const handlePowerChangeEvent = (state: string) =>
        handleConsoleOutput(text('Server state') + ': ' + text(state), true);

    const handleCommandKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
        if (e.key === 'ArrowUp') {
            const newIndex = Math.min(historyIndex + 1, history!.length - 1);

            setHistoryIndex(newIndex);
            e.currentTarget.value = history![newIndex] || '';

            // By default up arrow will also bring the cursor to the start of the line,
            // so we'll preventDefault to keep it at the end.
            e.preventDefault();
        }

        if (e.key === 'ArrowDown') {
            const newIndex = Math.max(historyIndex - 1, -1);

            setHistoryIndex(newIndex);
            e.currentTarget.value = history![newIndex] || '';
        }

        const command = e.currentTarget.value;
        if (e.key === 'Enter' && command.length > 0) {
            setHistory((prevHistory) => [command, ...prevHistory!].slice(0, 32));
            setHistoryIndex(-1);

            instance && instance.send('send command', command);
            e.currentTarget.value = '';
        }
    };

    useEffect(() => {
        if (connected && ref.current && !terminal.element) {
            terminal.loadAddon(fitAddon);
            terminal.loadAddon(searchAddon);
            terminal.loadAddon(searchBar);
            terminal.loadAddon(webLinksAddon);
            terminal.loadAddon(unicode11Addon);
            terminal.loadAddon(scrollDownHelperAddon);

            terminal.open(ref.current);

            // Activate Unicode 11 for proper emoji and special character width handling
            terminal.unicode.activeVersion = '11';

            fitAddon.fit();
            searchBar.addNewStyle(zIndex);

            // Add support for capturing keys
            terminal.attachCustomKeyEventHandler((e: KeyboardEvent) => {
                if ((e.ctrlKey || e.metaKey) && e.key === 'c') {
                    document.execCommand('copy');
                    return false;
                } else if ((e.ctrlKey || e.metaKey) && e.key === 'f') {
                    e.preventDefault();
                    searchBar.show();
                    return false;
                } else if (e.key === 'Escape') {
                    searchBar.hidden();
                }
                return true;
            });
        }
    }, [terminal, connected]);

    useEventListener(
        'resize',
        debounce(() => {
            if (terminal.element) {
                fitAddon.fit();
            }
        }, 100)
    );

    useEffect(() => {
        const listeners: Record<string, (s: string) => void> = {
            [SocketEvent.STATUS]: handlePowerChangeEvent,
            [SocketEvent.CONSOLE_OUTPUT]: handleConsoleOutput,
            [SocketEvent.INSTALL_OUTPUT]: handleConsoleOutput,
            [SocketEvent.TRANSFER_LOGS]: handleConsoleOutput,
            [SocketEvent.TRANSFER_STATUS]: handleTransferStatus,
            [SocketEvent.DAEMON_MESSAGE]: (line) => handleConsoleOutput(line, true),
            [SocketEvent.DAEMON_ERROR]: handleDaemonErrorOutput,
        };

        if (connected && instance) {
            // Do not clear the console if the server is being transferred.
            if (!isTransferring) {
                terminal.clear();
            }

            Object.keys(listeners).forEach((key: string) => {
                instance.addListener(key, listeners[key]);
            });
            instance.send(SocketRequest.SEND_LOGS);
        }

        return () => {
            if (instance) {
                Object.keys(listeners).forEach((key: string) => {
                    instance.removeListener(key, listeners[key]);
                });
            }
        };
    }, [connected, instance]);

    return (
        <div className={classNames(styles.terminal, 'relative')}>
            <div className={'flex flex-wrap items-center gap-2 bg-neutral-900 p-3 rounded-t text-xs'}>
                <span role={'status'} className={connected ? 'text-green-400' : 'text-yellow-400'}>
                    {text(connected ? 'Connected' : 'Disconnected')}
                </span>
                <input
                    aria-label={text('Search console')}
                    placeholder={text('Search console')}
                    className={'bg-neutral-800 border border-neutral-600 rounded px-2 py-1 min-w-0'}
                    value={query}
                    onChange={(event) => setQuery(event.target.value)}
                    onKeyDown={(event) => {
                        if (event.key === 'Enter') {
                            event.preventDefault();
                            search(event.shiftKey);
                        }
                    }}
                />
                <button type={'button'} disabled={!query || !connected} onClick={() => search(true)}>
                    {text('Previous')}
                </button>
                <button type={'button'} disabled={!query || !connected} onClick={() => search()}>
                    {text('Next')}
                </button>
                <button
                    type={'button'}
                    onClick={async () => {
                        try {
                            await navigator.clipboard.writeText(
                                terminal.getSelection() || consoleText(terminal.buffer.active)
                            );
                            setNotice('Copied to clipboard.');
                        } catch {
                            setNotice('Copy failed. Use selection and Ctrl+C.');
                        }
                    }}
                >
                    {text('Copy')}
                </button>
                <button type={'button'} onClick={downloadLog} title={text('Visible buffer only (up to 5000 lines).')}>
                    {text('Download log')}
                </button>
                <button type={'button'} onClick={() => terminal.reset()}>
                    {text('Clear screen')}
                </button>
                <label className={'flex items-center gap-1'}>
                    <input
                        type={'checkbox'}
                        checked={follow}
                        onChange={(event) => {
                            followRef.current = event.target.checked;
                            setFollow(event.target.checked);
                            if (event.target.checked) terminal.scrollToBottom();
                        }}
                    />
                    {text('Follow output')}
                </label>
                <label className={'flex items-center gap-1'}>
                    {text('Font size')}
                    <select
                        className={'bg-neutral-800 rounded'}
                        value={fontSize}
                        onChange={(event) => setFontSize(Number(event.target.value))}
                    >
                        {[12, 14, 16, 18, 20].map((size) => (
                            <option key={size} value={size}>
                                {size}
                            </option>
                        ))}
                    </select>
                </label>
                {canSendCommands && (
                    <button
                        type={'button'}
                        onClick={() => {
                            setHistory([]);
                            setHistoryIndex(-1);
                            setNotice('Command history cleared.');
                        }}
                    >
                        {text('Clear command history')}
                    </button>
                )}
                <span role={'status'} aria-live={'polite'}>
                    {notice && text(notice)}
                </span>
            </div>
            <div
                className={classNames(styles.container, styles.overflows_container, 'relative', {
                    'rounded-b': !canSendCommands,
                })}
            >
                <SpinnerOverlay visible={!connected} size={'large'} />
                <div className={'h-full'}>
                    <div id={styles.terminal} ref={ref} />
                </div>
            </div>
            {canSendCommands && (
                <div className={classNames('relative', styles.overflows_container)}>
                    <input
                        className={classNames('peer', styles.command_input)}
                        type={'text'}
                        placeholder={text('Type a command...')}
                        aria-label={text('Console command input.')}
                        disabled={!instance || !connected}
                        onKeyDown={handleCommandKeyDown}
                        autoCorrect={'off'}
                        autoCapitalize={'none'}
                    />
                    <div
                        className={classNames(
                            'text-gray-100 peer-focus:text-gray-50 peer-focus:animate-pulse',
                            styles.command_icon
                        )}
                    >
                        <ChevronDoubleRightIcon className={'w-4 h-4'} />
                    </div>
                </div>
            )}
        </div>
    );
};
