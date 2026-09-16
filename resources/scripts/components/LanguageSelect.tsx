import React from 'react';
import { useTranslation } from 'react-i18next';
import usePanelText from '@/plugins/usePanelText';

export default function LanguageSelect() {
    const { i18n } = useTranslation('fork');
    const text = usePanelText();
    return (
        <select
            aria-label={text('Language')}
            className={'mx-2 rounded bg-neutral-800 text-neutral-100 text-sm px-2 py-1 border border-neutral-600'}
            value={i18n.language === 'hu' ? 'hu' : 'en'}
            onChange={(event) => {
                const language = event.target.value;
                try {
                    localStorage.setItem('alex-panel:language:v1', language);
                } catch {
                    /* Browser storage is optional. */
                }
                void i18n.changeLanguage(language);
                document.documentElement.lang = language;
            }}
        >
            <option value={'hu'}>Magyar</option>
            <option value={'en'}>English</option>
        </select>
    );
}
