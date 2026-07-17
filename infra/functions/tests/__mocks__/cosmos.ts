// Mock for ../shared/cosmos — returns empty results by default
export const mockFetchAll = jest.fn().mockResolvedValue({ resources: [] });

// container.item(id, pk).read() — no existing document by default, i.e. the
// incoming record is treated as new for last-write-wins purposes.
export const mockItemRead = jest.fn().mockResolvedValue({ resource: undefined });

export const mockItems = {
  query: jest.fn().mockReturnValue({ fetchAll: mockFetchAll }),
  upsert: jest.fn().mockResolvedValue({}),
};

export const mockContainer = {
  items: mockItems,
  item: jest.fn().mockReturnValue({ read: mockItemRead }),
};

export const mockDatabase = {
  container: jest.fn().mockReturnValue(mockContainer),
};

export const getDatabase = jest.fn().mockReturnValue(mockDatabase);

export function resetCosmosDb() {
  mockFetchAll.mockResolvedValue({ resources: [] });
  mockItemRead.mockResolvedValue({ resource: undefined });
  mockContainer.item.mockReturnValue({ read: mockItemRead });
  mockDatabase.container.mockReturnValue(mockContainer);
}
