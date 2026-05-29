/**
 * Unit tests for ExecutionEngine control-flow logic.
 * We mock the Playwright Page to avoid a real browser in unit tests.
 */
import { ExecutionEngine } from '../src/engine/execution.engine';
import { ScopeManager } from '../src/scope/scope.manager';
import { Instruction } from '../src/types/instructions.types';

// Minimal Page mock
function createPageMock(overrides: Partial<Record<string, jest.Mock>> = {}) {
  return {
    goto: jest.fn().mockResolvedValue(undefined),
    click: jest.fn().mockResolvedValue(undefined),
    fill: jest.fn().mockResolvedValue(undefined),
    waitForTimeout: jest.fn().mockResolvedValue(undefined),
    evaluate: jest.fn().mockResolvedValue(undefined),
    on: jest.fn(),
    off: jest.fn(),
    locator: jest.fn().mockReturnValue({ count: jest.fn().mockResolvedValue(0) }),
    ...overrides,
  };
}

describe('ExecutionEngine', () => {
  let engine: ExecutionEngine;

  beforeEach(() => {
    engine = new ExecutionEngine();
  });

  it('should execute goto instruction', async () => {
    const page = createPageMock();
    const scope = new ScopeManager();
    const instructions: Instruction[] = [
      { type: 'goto', url: 'https://example.com' },
    ];

    await engine.run(instructions, page as any, scope);
    expect(page.goto).toHaveBeenCalledWith('https://example.com', expect.any(Object));
  });

  it('should execute fill with resolved variable', async () => {
    const page = createPageMock();
    const scope = new ScopeManager();
    scope.merge({ email: 'user@example.com' });

    const instructions: Instruction[] = [
      { type: 'fill', selector: 'input', value: '$email' },
    ];

    await engine.run(instructions, page as any, scope);
    expect(page.fill).toHaveBeenCalledWith('input', 'user@example.com');
  });

  it('should not throw on optional click miss', async () => {
    const page = createPageMock({
      click: jest.fn().mockRejectedValue(new Error('Element not found')),
    });
    const scope = new ScopeManager();
    const instructions: Instruction[] = [
      { type: 'click', selector: '.optional-btn', optional: true },
    ];

    await expect(engine.run(instructions, page as any, scope)).resolves.not.toThrow();
  });

  it('should jump to label on jump instruction', async () => {
    const page = createPageMock();
    const scope = new ScopeManager();
    const visited: string[] = [];

    // Using evaluate to track execution order
    page.evaluate = jest.fn().mockImplementation(async (fn: any, id: string) => {
      visited.push(id);
      return id;
    });

    const instructions: Instruction[] = [
      { type: 'evaluate', script: '(id) => id', args: ['step-a'], saveAs: 'a' },
      { type: 'jump', to: 'skip-b' },
      { type: 'evaluate', script: '(id) => id', args: ['step-b'], saveAs: 'b' }, // should be skipped
      { type: 'label', name: 'skip-b' },
      { type: 'evaluate', script: '(id) => id', args: ['step-c'], saveAs: 'c' },
    ];

    await engine.run(instructions, page as any, scope);
    expect(visited).toEqual(['step-a', 'step-c']);
    expect(visited).not.toContain('step-b');
  });

  it('should jump on if condition when scope value matches', async () => {
    const page = createPageMock();
    page.locator = jest.fn().mockReturnValue({ count: jest.fn().mockResolvedValue(0) });

    const scope = new ScopeManager();
    scope.merge({ isLoggedIn: true });

    const visited: string[] = [];
    page.evaluate = jest.fn().mockImplementation(async (fn: any, id: string) => {
      visited.push(id);
      return id;
    });

    const instructions: Instruction[] = [
      {
        type: 'if',
        condition: { type: 'scopeEvaluate', left: '$isLoggedIn', operator: '===', right: true },
        jumpTo: 'already-logged',
      },
      { type: 'evaluate', script: '(id) => id', args: ['login-step'], saveAs: 'x' },
      { type: 'label', name: 'already-logged' },
      { type: 'evaluate', script: '(id) => id', args: ['dashboard'], saveAs: 'y' },
    ];

    await engine.run(instructions, page as any, scope);
    expect(visited).toEqual(['dashboard']);
    expect(visited).not.toContain('login-step');
  });

  it('should set scope fields via set instruction', async () => {
    const page = createPageMock();
    const scope = new ScopeManager();
    const instructions: Instruction[] = [
      { type: 'set', fields: { retryCount: 0, status: 'pending' } },
    ];

    await engine.run(instructions, page as any, scope);
    expect(scope.get('retryCount')).toBe(0);
    expect(scope.get('status')).toBe('pending');
  });

  it('should throw on invalid label in jump', async () => {
    const page = createPageMock();
    const scope = new ScopeManager();
    const instructions: Instruction[] = [
      { type: 'jump', to: 'nonexistent-label' },
    ];

    await expect(engine.run(instructions, page as any, scope)).rejects.toThrow(
      'Label not found: "nonexistent-label"',
    );
  });
});
