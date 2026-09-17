import React from 'react';
import tw from 'twin.macro';
import Select from '@/components/elements/Select';
import Tooltip from '@/components/elements/tooltip/Tooltip';
import usePanelText from '@/plugins/usePanelText';
import usePanelTheme from '@/plugins/usePanelTheme';
import { panelThemes, panelThemeLabels } from '@/theme';

export default () => {
    const text = usePanelText();
    const [theme, setTheme] = usePanelTheme();

    return (
        <Tooltip placement={'bottom'} content={text('Theme')}>
            <Select
                aria-label={text('Theme')}
                value={theme}
                onChange={(event) => setTheme(event.currentTarget.value as typeof theme)}
                css={tw`h-full py-0 px-2 border-0 bg-transparent text-neutral-300 cursor-pointer`}
            >
                {panelThemes.map((item) => (
                    <option key={item} value={item}>
                        {text(panelThemeLabels[item])}
                    </option>
                ))}
            </Select>
        </Tooltip>
    );
};
