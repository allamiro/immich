import ServerStatus from '#lib/components/shared-components/side-bar/ServerStatus.svelte';
import { websocketStore } from '#lib/stores/websocket.ts';
import { test } from '#test/unit/fixtures.ts';
import { afterEach, expect } from 'vitest';
import { page } from 'vitest/browser';

const version = { major: 3, minor: 4, patch: 1, prerelease: null, featureLevel: 1 };

afterEach(() => {
  websocketStore.connected.set(false);
  websocketStore.serverVersion.set(undefined as never);
});

test('shows the version label the server reports in its about info', async ({ data, render, settle }) => {
  Object.assign(data.aboutInfo, { version: 'v3.4.1-fork.1' });
  websocketStore.connected.set(true);
  websocketStore.serverVersion.set(version);

  await render(ServerStatus, () => Promise.resolve({}));
  await settle();

  await expect.element(page.getByRole('button', { name: 'v3.4.1-fork.1' })).toBeVisible();
});
