class LRU
  def initialize(capacity)
    @capacity = capacity
    @store = {}
    @order = []
  end

  def put(key, value)
    if @store.has_key?(key)
      # Move the key to the end to show it was recently used
      @order.delete(key)
    elsif @store.size >= @capacity
      # If the cache is at capacity, we need to remove the least recently used item
      lru_key = @order.shift
      @store.delete(lru_key)
    end

    @store[key] = value
    @order.push(key)
  end

  def get(key)
    return nil unless @store.has_key?(key)

    # Move the key to the end to show it was recently used
    @order.delete(key)
    @order.push(key)

    @store[key]
  end

  def to_s
    @store.to_s
  end
end