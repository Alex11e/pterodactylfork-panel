import tw from 'twin.macro';
import { createGlobalStyle } from 'styled-components/macro';
// @ts-expect-error untyped font file
import font from '@fontsource-variable/ibm-plex-sans/files/ibm-plex-sans-latin-wght-normal.woff2';

export default createGlobalStyle`
    @font-face {
        font-family: 'IBM Plex Sans';
        font-style: normal;
        font-display: swap;
        font-weight: 100 700;
        src: url(${font}) format('woff2-variations');
        unicode-range: U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD;
    }

    body {
        ${tw`font-sans bg-neutral-800 text-neutral-200`};
        letter-spacing: 0.015em;
    }

    /* Built-in fork themes. Tailwind utility colors are overridden here so
       existing Blueprint-style components inherit the selected palette. */
    body[data-panel-theme] {
        --panel-bg: #1f2937;
        --panel-surface: #111827;
        --panel-raised: #374151;
        --panel-input: #4b5563;
        --panel-text: #e5e7eb;
        --panel-muted: #9ca3af;
        background-color: var(--panel-bg) !important;
        color: var(--panel-text) !important;
    }

    body[data-panel-theme='emerald'] {
        --panel-bg: #071b17;
        --panel-surface: #092923;
        --panel-raised: #123d33;
        --panel-input: #1b5446;
        --panel-text: #e3fff5;
        --panel-muted: #9ad6c4;
    }

    body[data-panel-theme='amethyst'] {
        --panel-bg: #171226;
        --panel-surface: #21183a;
        --panel-raised: #3a2a5c;
        --panel-input: #523b78;
        --panel-text: #f4edff;
        --panel-muted: #c7b9e5;
    }

    body[data-panel-theme='sunset'] {
        --panel-bg: #25151a;
        --panel-surface: #351b22;
        --panel-raised: #5a2c31;
        --panel-input: #754039;
        --panel-text: #fff1e6;
        --panel-muted: #e8b9a5;
    }

    body[data-panel-theme='dracula'] {
        --panel-bg: #282a36;
        --panel-surface: #21222c;
        --panel-raised: #44475a;
        --panel-input: #6272a4;
        --panel-text: #f8f8f2;
        --panel-muted: #bdc0d0;
    }

    body[data-panel-theme='nord'] {
        --panel-bg: #2e3440;
        --panel-surface: #3b4252;
        --panel-raised: #434c5e;
        --panel-input: #4c566a;
        --panel-text: #eceff4;
        --panel-muted: #b8c0ce;
    }

    body[data-panel-theme='ocean'] {
        --panel-bg: #071923;
        --panel-surface: #0b2533;
        --panel-raised: #123b4d;
        --panel-input: #1b5870;
        --panel-text: #e6f7ff;
        --panel-muted: #9cc8d9;
    }

    body[data-panel-theme] .bg-neutral-900 { background-color: var(--panel-surface) !important; }
    body[data-panel-theme] .bg-neutral-800 { background-color: var(--panel-bg) !important; }
    body[data-panel-theme] .bg-neutral-700 { background-color: var(--panel-raised) !important; }
    body[data-panel-theme] .bg-neutral-600,
    body[data-panel-theme] .bg-neutral-500 { background-color: var(--panel-input) !important; }
    body[data-panel-theme] .text-neutral-100,
    body[data-panel-theme] .text-neutral-200,
    body[data-panel-theme] .text-neutral-300 { color: var(--panel-text) !important; }
    body[data-panel-theme] .text-neutral-400,
    body[data-panel-theme] .text-neutral-500,
    body[data-panel-theme] .text-neutral-600 { color: var(--panel-muted) !important; }

    h1, h2, h3, h4, h5, h6 {
        ${tw`font-medium tracking-normal font-header`};
    }

    p {
        ${tw`text-neutral-200 leading-snug font-sans`};
    }

    form {
        ${tw`m-0`};
    }

    textarea, select, input, button, button:focus, button:focus-visible {
        ${tw`outline-none`};
    }

    input[type=number]::-webkit-outer-spin-button,
    input[type=number]::-webkit-inner-spin-button {
        -webkit-appearance: none !important;
        margin: 0;
    }

    input[type=number] {
        -moz-appearance: textfield !important;
    }

    /* Scroll Bar Style */
    ::-webkit-scrollbar {
        background: none;
        width: 16px;
        height: 16px;
    }

    ::-webkit-scrollbar-thumb {
        border: solid 0 rgb(0 0 0 / 0%);
        border-right-width: 4px;
        border-left-width: 4px;
        -webkit-border-radius: 9px 4px;
        -webkit-box-shadow: inset 0 0 0 1px hsl(211, 10%, 53%), inset 0 0 0 4px hsl(209deg 18% 30%);
    }

    ::-webkit-scrollbar-track-piece {
        margin: 4px 0;
    }

    ::-webkit-scrollbar-thumb:horizontal {
        border-right-width: 0;
        border-left-width: 0;
        border-top-width: 4px;
        border-bottom-width: 4px;
        -webkit-border-radius: 4px 9px;
    }

    ::-webkit-scrollbar-corner {
        background: transparent;
    }
`;
