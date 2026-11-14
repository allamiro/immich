import { SemVer } from 'semver';
import { withoutForkSuffix } from 'src/utils/version.js';

describe(withoutForkSuffix.name, () => {
  it.each([
    ['3.4.1-fork.1', '3.4.1'],
    ['3.4.1-fork.12', '3.4.1'],
    ['3.4.0-rc.0-fork.1', '3.4.0-rc.0'],
    ['3.4.0-rc.0.fork.2', '3.4.0-rc.0'],
    ['3.4.1', '3.4.1'],
    ['3.4.0-rc.0', '3.4.0-rc.0'],
    ['3.4.1-forked.1', '3.4.1-forked.1'],
    ['3.4.1-fork', '3.4.1-fork'],
  ])('should turn %s into %s', (input, expected) => {
    expect(withoutForkSuffix(new SemVer(input)).version).toBe(expected);
  });

  it('should keep the prerelease number of an upstream release candidate', () => {
    expect(withoutForkSuffix(new SemVer('3.4.0-rc.2-fork.1')).prerelease).toEqual(['rc', 2]);
  });

  it('should leave no prerelease on a fork of a stable release', () => {
    expect(withoutForkSuffix(new SemVer('3.4.1-fork.1')).prerelease).toEqual([]);
  });
});
