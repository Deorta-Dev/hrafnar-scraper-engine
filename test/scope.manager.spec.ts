import { ScopeManager } from '../src/scope/scope.manager';

describe('ScopeManager', () => {
  let scope: ScopeManager;

  beforeEach(() => {
    scope = new ScopeManager();
  });

  describe('merge & get', () => {
    it('should merge fields into scope', () => {
      scope.merge({ user: { name: 'Juan', age: 30 } });
      expect(scope.get('user.name')).toBe('Juan');
      expect(scope.get('user.age')).toBe(30);
    });

    it('should deep merge without overwriting sibling keys', () => {
      scope.merge({ user: { name: 'Juan' } });
      scope.merge({ user: { age: 30 } });
      expect(scope.get('user.name')).toBe('Juan');
      expect(scope.get('user.age')).toBe(30);
    });
  });

  describe('set', () => {
    it('should set a nested value', () => {
      scope.set('auth.token', 'abc123');
      expect(scope.get('auth.token')).toBe('abc123');
    });
  });

  describe('hasKeys', () => {
    it('should return true when all keys exist', () => {
      scope.merge({ token: 'x', userId: '1' });
      expect(scope.hasKeys(['token', 'userId'])).toBe(true);
    });

    it('should return false when a key is missing', () => {
      scope.merge({ token: 'x' });
      expect(scope.hasKeys(['token', 'userId'])).toBe(false);
    });
  });

  describe('resolveDynamicValues', () => {
    beforeEach(() => {
      scope.merge({ user: { name: 'Juan', age: 30 }, token: 'secret' });
    });

    it('should resolve a top-level $variable', () => {
      expect(scope.resolveDynamicValues('$token')).toBe('secret');
    });

    it('should resolve nested $variable paths', () => {
      expect(scope.resolveDynamicValues('$user.name')).toBe('Juan');
    });

    it('should leave non-$ strings unchanged', () => {
      expect(scope.resolveDynamicValues('hello')).toBe('hello');
    });

    it('should recursively resolve inside objects', () => {
      const resolved = scope.resolveDynamicValues({
        name: '$user.name',
        age: '$user.age',
        static: 'no change',
      });
      expect(resolved).toEqual({
        name: 'Juan',
        age: 30,
        static: 'no change',
      });
    });

    it('should recursively resolve inside arrays', () => {
      const resolved = scope.resolveDynamicValues(['$token', 'plain']);
      expect(resolved).toEqual(['secret', 'plain']);
    });

    it('should return original string for unknown $path', () => {
      expect(scope.resolveDynamicValues('$unknown.path')).toBe('$unknown.path');
    });

    it('should not modify non-string primitives', () => {
      expect(scope.resolveDynamicValues(42)).toBe(42);
      expect(scope.resolveDynamicValues(true)).toBe(true);
      expect(scope.resolveDynamicValues(null)).toBe(null);
    });
  });

  describe('resolveProject', () => {
    it('should resolve a project template', () => {
      scope.merge({ title: 'Hello', count: 5 });
      const result = scope.resolveProject({
        heading: '$title',
        stats: { items: '$count' },
      });
      expect(result).toEqual({ heading: 'Hello', stats: { items: 5 } });
    });
  });

  describe('reset', () => {
    it('should clear all scope data', () => {
      scope.merge({ x: 1 });
      scope.reset();
      expect(scope.getScope()).toEqual({});
    });
  });
});
