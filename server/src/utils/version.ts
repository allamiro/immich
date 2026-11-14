import { SemVer } from 'semver';

const FORK_SUFFIX = /[-.]fork\.\d+$/;

export const withoutForkSuffix = (version: SemVer) => new SemVer(version.version.replace(FORK_SUFFIX, ''));
