import { useTranslation } from 'react-i18next';

export default function usePanelText() {
    const { t } = useTranslation('fork');
    return (key: string): string => t(key, { keySeparator: false, defaultValue: key });
}
