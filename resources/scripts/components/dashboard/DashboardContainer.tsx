import React, { useEffect, useMemo, useState } from 'react';
import { Server } from '@/api/server/getServer';
import getServers from '@/api/getServers';
import ServerRow from '@/components/dashboard/ServerRow';
import Spinner from '@/components/elements/Spinner';
import PageContentBlock from '@/components/elements/PageContentBlock';
import useFlash from '@/plugins/useFlash';
import { useStoreState } from 'easy-peasy';
import { usePersistedState } from '@/plugins/usePersistedState';
import Switch from '@/components/elements/Switch';
import tw from 'twin.macro';
import useSWR from 'swr';
import { PaginatedResult } from '@/api/http';
import Pagination from '@/components/elements/Pagination';
import { useLocation } from 'react-router-dom';
import Input from '@/components/elements/Input';
import Select from '@/components/elements/Select';
import usePanelText from '@/plugins/usePanelText';

export default () => {
    const { search } = useLocation();
    const defaultPage = Number(new URLSearchParams(search).get('page') || '1');

    const [page, setPage] = useState(!isNaN(defaultPage) && defaultPage > 0 ? defaultPage : 1);
    const { clearFlashes, clearAndAddHttpError } = useFlash();
    const uuid = useStoreState((state) => state.user.data!.uuid);
    const rootAdmin = useStoreState((state) => state.user.data!.rootAdmin);
    const [showOnlyAdmin, setShowOnlyAdmin] = usePersistedState(`${uuid}:show_all_servers`, false);
    const [query, setQuery] = useState('');
    const [favorites, setFavorites] = usePersistedState<string[]>(`${uuid}:favorite_servers`, []);
    const [favoriteOnly, setFavoriteOnly] = useState(false);
    const [compact, setCompact] = usePersistedState(`${uuid}:compact_dashboard`, false);
    const text = usePanelText();
    const favoriteIds = favorites ?? [];

    const { data: servers, error } = useSWR<PaginatedResult<Server>>(
        ['/api/client/servers', showOnlyAdmin && rootAdmin, page, query],
        () => getServers({ page, query: query.trim() || undefined, type: showOnlyAdmin && rootAdmin ? 'admin' : undefined })
    );

    useEffect(() => setPage(1), [showOnlyAdmin, query, favoriteOnly]);

    const visibleServers = useMemo(() => {
        if (!servers) return [];
        const filtered = favoriteOnly ? servers.items.filter((server) => favoriteIds.includes(server.uuid)) : servers.items;
        return [...filtered].sort((a, b) => {
            const favoriteOrder = Number(favoriteIds.includes(b.uuid)) - Number(favoriteIds.includes(a.uuid));
            return favoriteOrder || a.name.localeCompare(b.name);
        });
    }, [servers, favoriteOnly, favoriteIds]);

    const toggleFavorite = (server: Server) => {
        setFavorites((current) =>
            (current ?? []).includes(server.uuid)
                ? (current ?? []).filter((uuid) => uuid !== server.uuid)
                : [...(current ?? []), server.uuid]
        );
    };

    useEffect(() => {
        if (!servers) return;
        if (servers.pagination.currentPage > 1 && !servers.items.length) {
            setPage(1);
        }
    }, [servers?.pagination.currentPage]);

    useEffect(() => {
        // Don't use react-router to handle changing this part of the URL, otherwise it
        // triggers a needless re-render. We just want to track this in the URL incase the
        // user refreshes the page.
        window.history.replaceState(null, document.title, `/${page <= 1 ? '' : `?page=${page}`}`);
    }, [page]);

    useEffect(() => {
        if (error) clearAndAddHttpError({ key: 'dashboard', error });
        if (!error) clearFlashes('dashboard');
    }, [error]);

    return (
        <PageContentBlock title={'Dashboard'} showFlashKey={'dashboard'}>
            <div css={tw`mb-4 flex flex-col sm:flex-row gap-2 sm:items-center`}>
                <Input
                    value={query}
                    onChange={(event) => setQuery(event.currentTarget.value)}
                    placeholder={text('Search servers')}
                    aria-label={text('Search servers')}
                    css={tw`flex-1`}
                />
                <Select value={favoriteOnly ? 'favorites' : 'all'} onChange={(event) => setFavoriteOnly(event.target.value === 'favorites')} css={tw`sm:w-48`}>
                    <option value={'all'}>{text('All servers')}</option>
                    <option value={'favorites'}>{text('Favorites')}</option>
                </Select>
                {rootAdmin && (
                    <p css={tw`uppercase text-xs text-neutral-400 mr-2`}>
                        {showOnlyAdmin ? "Showing others' servers" : 'Showing your servers'}
                    </p>
                )}
                {rootAdmin && <Switch name={'show_all_servers'} defaultChecked={showOnlyAdmin} onChange={() => setShowOnlyAdmin((s) => !s)} />}
                <span css={tw`uppercase text-xs text-neutral-400 ml-2`}>{text('Compact view')}</span>
                <Switch name={'compact_dashboard'} defaultChecked={compact} onChange={() => setCompact((value) => !value)} />
            </div>
            {!servers ? (
                <Spinner centered size={'large'} />
            ) : (
                <Pagination data={{ ...servers, items: visibleServers }} onPageSelect={setPage}>
                    {() =>
                        visibleServers.length > 0 ? (
                            visibleServers.map((server, index) => (
                                <ServerRow
                                    key={server.uuid}
                                    server={server}
                                    isFavorite={favoriteIds.includes(server.uuid)}
                                    onToggleFavorite={() => toggleFavorite(server)}
                                    compact={compact ?? false}
                                    css={index > 0 ? tw`mt-2` : undefined}
                                />
                            ))
                        ) : (
                            <p css={tw`text-center text-sm text-neutral-400`}>
                                {showOnlyAdmin
                                    ? text('There are no other servers to display.')
                                    : favoriteOnly
                                    ? text('No favorite servers yet.')
                                    : text('There are no servers associated with your account.')}
                            </p>
                        )
                    }
                </Pagination>
            )}
        </PageContentBlock>
    );
};
