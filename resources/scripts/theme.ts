import { BreakpointFunction, createBreakpoint } from 'styled-components-breakpoint';

type Breakpoints = 'xs' | 'sm' | 'md' | 'lg' | 'xl';
export const breakpoint: BreakpointFunction<Breakpoints> = createBreakpoint<Breakpoints>({
    xs: 0,
    sm: 640,
    md: 768,
    lg: 1024,
    xl: 1280,
});

export const panelThemes = ['midnight', 'emerald', 'amethyst', 'sunset'] as const;
export type PanelTheme = (typeof panelThemes)[number];

export const panelThemeLabels: Record<PanelTheme, string> = {
    midnight: 'Midnight',
    emerald: 'Emerald',
    amethyst: 'Amethyst',
    sunset: 'Sunset',
};
