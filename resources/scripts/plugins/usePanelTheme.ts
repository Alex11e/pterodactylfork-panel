import { useEffect, useState } from 'react';
import { panelThemes, PanelTheme } from '@/theme';

const STORAGE_KEY = 'alex-panel:theme';
const isPanelTheme = (value: string | null): value is PanelTheme =>
    value !== null && (panelThemes as readonly string[]).includes(value);

export default function usePanelTheme(): [PanelTheme, (theme: PanelTheme) => void] {
    const [theme, setTheme] = useState<PanelTheme>(() => {
        try {
            const stored = window.localStorage.getItem(STORAGE_KEY);
            return isPanelTheme(stored) ? stored : 'midnight';
        } catch {
            return 'midnight';
        }
    });

    useEffect(() => {
        document.body.dataset.panelTheme = theme;
        try {
            window.localStorage.setItem(STORAGE_KEY, theme);
        } catch {
            // Private browsing can disable localStorage; the in-memory choice still works.
        }
    }, [theme]);

    return [theme, setTheme];
}
