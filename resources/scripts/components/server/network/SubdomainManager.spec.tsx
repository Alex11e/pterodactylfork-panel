/** @jest-environment jsdom */
import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import SubdomainManager from './SubdomainManager';
import http from '@/api/http';
import useSWR from 'swr';

jest.mock('swr');
jest.mock('@/api/http', () => ({
    __esModule: true,
    default: { request: jest.fn() },
    httpErrorToHuman: () => 'Provider failed',
}));
jest.mock('@/state/server', () => ({ ServerContext: { useStoreState: () => 'test-server' } }));
jest.mock('@/plugins/usePanelText', () => ({ __esModule: true, default: () => (key: string) => key }));

const mutate = jest.fn().mockResolvedValue(undefined);
const record = { hostname: 'survival.games.example.com', ip: '8.8.8.8', port: 25565, status: 'active' };
const state = (overrides = {}) =>
    (useSWR as jest.Mock).mockReturnValue({
        data: {
            enabled: true,
            domain: 'games.example.com',
            can_manage: true,
            record: null,
            ...overrides,
        },
        mutate,
    });

beforeEach(() => {
    jest.clearAllMocks();
    (http.request as jest.Mock).mockResolvedValue({});
    state();
});

it('creates a label through the current server endpoint', async () => {
    render(<SubdomainManager />);
    fireEvent.change(screen.getByLabelText('Server address'), { target: { value: 'SURVIVAL' } });
    fireEvent.click(screen.getByText('Create subdomain'));
    await waitFor(() =>
        expect(http.request).toHaveBeenCalledWith({
            method: 'post',
            url: '/api/client/servers/test-server/network/subdomain',
            timeout: 60000,
            data: { label: 'survival' },
        })
    );
    await waitFor(() => expect(mutate).toHaveBeenCalled());
});

it('requires confirmation before deleting and allows cancelling', async () => {
    state({ record });
    render(<SubdomainManager />);
    fireEvent.click(screen.getByText('Delete subdomain'));
    expect(http.request).not.toHaveBeenCalled();
    fireEvent.click(screen.getByText('Cancel'));
    expect(screen.queryByText('Confirm deletion')).not.toBeInTheDocument();
    fireEvent.click(screen.getByText('Delete subdomain'));
    fireEvent.click(screen.getByText('Confirm deletion'));
    await waitFor(() => expect(http.request).toHaveBeenCalledWith(expect.objectContaining({ method: 'delete' })));
});

it('does not offer mutation controls to subusers', () => {
    state({ record, can_manage: false });
    render(<SubdomainManager />);
    expect(screen.getByText('Copy address')).toBeInTheDocument();
    expect(screen.queryByText('Sync')).not.toBeInTheDocument();
    expect(screen.queryByText('Delete subdomain')).not.toBeInTheDocument();
});

it('refreshes state after provider failure so a pending reservation can be recovered', async () => {
    state({ record: { ...record, status: 'pending' } });
    (http.request as jest.Mock).mockRejectedValue(new Error('timeout'));
    render(<SubdomainManager />);
    fireEvent.click(screen.getByText('Sync'));
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Provider failed'));
    await waitFor(() => expect(mutate).toHaveBeenCalled());
});
