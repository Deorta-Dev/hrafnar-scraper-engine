export type InstructionType =
  | 'goto'
  | 'click'
  | 'fill'
  | 'wait'
  | 'label'
  | 'jump'
  | 'if'
  | 'set'
  | 'listenAndTrigger'
  | 'waitForListeners'
  | 'pageFetch'
  | 'evaluate';

export interface BaseInstruction {
  type: InstructionType;
}

// --- DOM Actions ---
export interface GotoInstruction extends BaseInstruction {
  type: 'goto';
  url: string;
  waitUntil?: 'load' | 'domcontentloaded' | 'networkidle';
}

export interface ClickInstruction extends BaseInstruction {
  type: 'click';
  selector: string;
  optional?: boolean;
}

export interface FillInstruction extends BaseInstruction {
  type: 'fill';
  selector: string;
  value: string;
}

export interface WaitInstruction extends BaseInstruction {
  type: 'wait';
  time: number;
}

// --- Control Flow ---
export interface LabelInstruction extends BaseInstruction {
  type: 'label';
  name: string;
}

export interface JumpInstruction extends BaseInstruction {
  type: 'jump';
  to: string;
}

export type ConditionType = 'elementExists' | 'scopeEvaluate';
export type Operator = '===' | '!==' | '>' | '<' | '>=' | '<=';

export interface ElementExistsCondition {
  type: 'elementExists';
  selector: string;
}

export interface ScopeEvaluateCondition {
  type: 'scopeEvaluate';
  left: string;
  operator: Operator;
  right: string | number | boolean;
}

export type Condition = ElementExistsCondition | ScopeEvaluateCondition;

export interface IfInstruction extends BaseInstruction {
  type: 'if';
  condition: Condition;
  jumpTo: string;
}

// --- State & Network ---
export interface SetInstruction extends BaseInstruction {
  type: 'set';
  fields: Record<string, unknown>;
}

export interface ListenConfig {
  urlPattern: string;
  extractKey?: string;
}

export interface TriggerConfig {
  type: 'click';
  selector: string;
}

export interface ListenAndTriggerInstruction extends BaseInstruction {
  type: 'listenAndTrigger';
  listen: ListenConfig;
  trigger: TriggerConfig;
  saveAs: string;
  timeout?: number;
}

export interface WaitForListenersInstruction extends BaseInstruction {
  type: 'waitForListeners';
  keys: string[];
  timeout?: number;
  pollInterval?: number;
}

// --- External Execution ---
export interface PageFetchInstruction extends BaseInstruction {
  type: 'pageFetch';
  url: string;
  options?: {
    method?: string;
    headers?: Record<string, string>;
    body?: string;
  };
  saveAs: string;
}

export interface EvaluateInstruction extends BaseInstruction {
  type: 'evaluate';
  script: string;
  args?: unknown[];
  saveAs?: string;
}

export type Instruction =
  | GotoInstruction
  | ClickInstruction
  | FillInstruction
  | WaitInstruction
  | LabelInstruction
  | JumpInstruction
  | IfInstruction
  | SetInstruction
  | ListenAndTriggerInstruction
  | WaitForListenersInstruction
  | PageFetchInstruction
  | EvaluateInstruction;

// --- API Payloads ---
export interface ExecutePayload {
  sessionId?: string;
  instructions: Instruction[];
  project?: Record<string, unknown>;
  closeSession?: boolean;
}

export interface ApiResponse<T = unknown> {
  status: 'success' | 'error';
  data?: T;
  error?: string;
  message?: string;
}
