// Mock for ../shared/cosmos — returns empty results by default
export const mockFetchAll = jest.fn().mockResolvedValue({ resources: [] });

export const mockItems = {
  query: jest.fn().mockReturnValue({ fetchAll: mockFetchAll }),
  upsert: jest.fn().mockResolvedValue({}),
};

export const mockContainer = {
  items: mockItems,
};

export const mockDatabase = {
  container: jest.fn().mockReturnValue(mockContainer),
};

export const getDatabase = jest.fn().mockReturnValue(mockDatabase);

export function resetCosmosDb() {
  mockFetchAll.mockResolvedValue({ resources: [] });
  mockDatabase.container.mockReturnValue(mockContainer);
}
