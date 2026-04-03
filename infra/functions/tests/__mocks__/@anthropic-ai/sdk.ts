// Minimal stub for @anthropic-ai/sdk used in chat function tests
export const mockStream = {
  [Symbol.asyncIterator]: async function* () {
    yield { type: "message_start" };
  },
};

export const mockMessagesCreate = jest.fn().mockResolvedValue({
  id: "msg_test",
  type: "message",
  role: "assistant",
  content: [{ type: "text", text: "Hello" }],
  model: "claude-haiku-4-5-20251001",
  stop_reason: "end_turn",
  usage: { input_tokens: 10, output_tokens: 5 },
});

export const mockMessagesStream = jest.fn().mockReturnValue(mockStream);

const Anthropic = jest.fn().mockImplementation(() => ({
  messages: {
    stream: mockMessagesStream,
    create: mockMessagesCreate,
  },
}));

// Attach APIError as a static property so `instanceof Anthropic.APIError` works
class APIError extends Error {
  status: number;
  constructor(message: string, status = 500) {
    super(message);
    this.status = status;
  }
}
(Anthropic as any).APIError = APIError;

export { APIError };
export default Anthropic;
