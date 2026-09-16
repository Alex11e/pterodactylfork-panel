import React, { useState } from 'react';
import useSWR from 'swr';
import tw from 'twin.macro';
import http, { httpErrorToHuman } from '@/api/http';
import { ServerContext } from '@/state/server';
import Button from '@/components/elements/Button';
import Input from '@/components/elements/Input';
import usePanelText from '@/plugins/usePanelText';

interface SubdomainState {
    enabled: boolean;
    domain: string;
    can_manage: boolean;
    record: null | { hostname: string; ip: string; port: number; status: string };
}

export default function SubdomainManager() {
    const t = usePanelText();
    const uuid = ServerContext.useStoreState((state) => state.server.data!.uuid);
    const url = `/api/client/servers/${uuid}/network/subdomain`;
    const { data, error, mutate } = useSWR<SubdomainState>(url, async (key) => (await http.get(key)).data);
    const [label, setLabel] = useState('');
    const [busy, setBusy] = useState(false);
    const [message, setMessage] = useState('');
    const [confirmDelete, setConfirmDelete] = useState(false);

    const change = async (method: 'post' | 'put' | 'delete') => {
        setBusy(true);
        setMessage('');
        try {
            await http.request({ method, url, timeout: 60000, data: method === 'post' ? { label } : undefined });
            setConfirmDelete(false);
            setMessage(t('DNS change saved. Propagation may take a few minutes.'));
        } catch (err) {
            setMessage(httpErrorToHuman(err));
        } finally {
            await mutate().catch(() => undefined);
            setBusy(false);
        }
    };

    const copy = async () => {
        if (!data?.record) return;
        try {
            await navigator.clipboard.writeText(`${data.record.hostname}:${data.record.port}`);
            setMessage(t('Address copied.'));
        } catch {
            setMessage(t('Copy failed. Select and copy the address manually.'));
        }
    };

    return (
        <section css={tw`mt-8 p-5 bg-neutral-700 rounded`} aria-labelledby={'subdomain-title'}>
            <h2 id={'subdomain-title'} css={tw`text-xl mb-3`}>
                {t('Subdomain manager')}
            </h2>
            {error ? (
                <p role={'alert'}>{httpErrorToHuman(error)}</p>
            ) : !data ? (
                <p>{t('Loading...')}</p>
            ) : (
                <>
                    {!data.enabled && (
                        <p>{t('Ask your administrator to enable Cloudflare DNS in the panel configuration.')}</p>
                    )}
                    {data.record ? (
                        <>
                            <p css={tw`font-mono text-lg break-all select-all`}>
                                {data.record.hostname}:{data.record.port}
                            </p>
                            <p css={tw`text-sm text-neutral-300 mt-2`}>
                                {data.record.ip} ·{' '}
                                {data.record.status === 'active'
                                    ? t('DNS saved')
                                    : t('Pending — use Sync or Delete to recover')}
                            </p>
                            <p css={tw`text-sm text-neutral-300 mt-2`}>
                                {t('After an allocation change, use Sync to update the IP and port.')}
                            </p>
                            <div css={tw`flex flex-wrap gap-2 mt-4`}>
                                <Button type={'button'} isSecondary onClick={copy}>
                                    {t('Copy address')}
                                </Button>
                                {data.can_manage && data.enabled && (
                                    <>
                                        <Button type={'button'} disabled={busy} onClick={() => change('put')}>
                                            {t('Sync')}
                                        </Button>
                                        <Button
                                            type={'button'}
                                            color={'red'}
                                            disabled={busy}
                                            onClick={() => setConfirmDelete(true)}
                                        >
                                            {t('Delete subdomain')}
                                        </Button>
                                    </>
                                )}
                            </div>
                            {confirmDelete && (
                                <div css={tw`mt-4`}>
                                    <p>{t('Delete this DNS address? The game server will keep running.')}</p>
                                    <div css={tw`flex gap-2 mt-2`}>
                                        <Button
                                            type={'button'}
                                            color={'red'}
                                            disabled={busy}
                                            onClick={() => change('delete')}
                                        >
                                            {t('Confirm deletion')}
                                        </Button>
                                        <Button
                                            type={'button'}
                                            isSecondary
                                            disabled={busy}
                                            onClick={() => setConfirmDelete(false)}
                                        >
                                            {t('Cancel')}
                                        </Button>
                                    </div>
                                </div>
                            )}
                        </>
                    ) : (
                        data.enabled &&
                        (data.can_manage ? (
                            <form
                                onSubmit={(event) => {
                                    event.preventDefault();
                                    change('post');
                                }}
                            >
                                <label htmlFor={'subdomain-label'}>{t('Server address')}</label>
                                <div css={tw`flex items-center gap-2 mt-2 mb-3`}>
                                    <Input
                                        id={'subdomain-label'}
                                        value={label}
                                        onChange={(event) => setLabel(event.target.value.toLowerCase())}
                                        pattern={'[a-z0-9]([a-z0-9-]*[a-z0-9])?'}
                                        maxLength={63}
                                        required
                                        disabled={busy}
                                        placeholder={'survival'}
                                    />
                                    <span css={tw`break-all`}>.{data.domain}</span>
                                </div>
                                <Button type={'submit'} disabled={busy || !label}>
                                    {t('Create subdomain')}
                                </Button>
                            </form>
                        ) : (
                            <p>{t('Only the server owner or an administrator can manage subdomains.')}</p>
                        ))
                    )}
                    <p css={tw`mt-4 text-sm text-neutral-300`}>
                        {t('DNS does not open firewall ports. Connect using the displayed address and port.')}
                    </p>
                </>
            )}
            {message && (
                <p role={'status'} css={tw`mt-4 text-sm`}>
                    {message}
                </p>
            )}
        </section>
    );
}
