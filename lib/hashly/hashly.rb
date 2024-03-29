module Hashly
  module_function

  def stringify_all_keys(hash)
    stringified_hash = {}
    hash.each do |k, v|
      stringified_hash[k.to_s] = v.is_a?(::Hash) ? stringify_all_keys(v) : v
    end
    stringified_hash
  end

  def symbolize_all_keys(hash)
    symbolized_hash = {}
    hash.each do |k, v|
      symbolized_hash[k.to_sym] = v.is_a?(::Hash) ? symbolize_all_keys(v) : v
    end
    symbolized_hash
  end

  # Evaluates the block on every key pair recursively. If any block is truthy, the method returns true, otherwise, false.
  def any?(hash, &block)
    raise 'hash is a required argument' if hash.nil?
    raise 'A block must be provided to this method to evaluate on each key pair. The evaluation occurs recursively. Block arguments: |k, v|' if block.nil?
    hash.each do |k, v|
      return true if yield(k, v)
      return true if v.is_a?(::Hash) && any?(v, &block) # recurse
    end
    false
  end

  # Sorts by key recursively - optionally include sorting of arrays
  def deep_sort(hash, include_arrays: true)
    raise "argument must be of type Hash - Actual type: #{hash.class}" unless hash.is_a?(::Hash)
    hash.each_with_object({}) do |(k, v), child_hash|
      child_hash[k] = case v
                      when ::Hash
                        deep_sort(v)
                      when ::Array
                        include_arrays ? v.sort : v
                      else
                        v
                      end
    end.sort.to_h
  end

  # Description:
  #   Merge two hashes with nested hashes recursively.
  # Returns:
  #   Hash with the merged data.
  # Parameters:
  #   boolean_or: use a boolean || operator on the base and override if they are not a Hash or Array instead of stomping with the override.
  #   left_outer_join_depth: Only merge keys that already exist in the base for the first X levels specified.
  #   modify_by_reference: Hashes will be modified by reference which will modify the actual parameters.
  #   selected_overrides: Allows for specifying a regex or value(s) that should ONLY be merged into the base Hash.
  #   excluded_overrides: Allows for specifying a regex or value(s) that should NOT be merged into the base Hash.
  def deep_merge(base, override, boolean_or: false, left_outer_join_depth: 0, modify_by_reference: false, selected_overrides: [], excluded_overrides: [])
    left_outer_join_depth -= 1 # decrement left_outer_join_depth for recursion
    return base if reject_value?(override, excluded_overrides)
    return base unless select_value?(override, selected_overrides)
    if base.nil?
      return nil if left_outer_join_depth >= 0
      return modify_by_reference || !override.is_a?(::Hash) ? override : override.dup
    end

    case override
    when nil
      base = base.dup unless modify_by_reference || !base.is_a?(::Hash) # duplicate hash to avoid modification by reference issues
      base # if override doesn't exist, simply return the existing value
    when ::Hash
      return override unless base.is_a?(::Hash)
      base = base.dup unless modify_by_reference || !base.is_a?(::Hash)
      override.each do |src_key, src_value|
        next if base[src_key].nil? && left_outer_join_depth >= 0 # if this is a left outer join and the key does not exist in the base, skip it
        base[src_key] = base[src_key] ? deep_merge(base[src_key], src_value, boolean_or: boolean_or, left_outer_join_depth: left_outer_join_depth, selected_overrides: selected_overrides, excluded_overrides: excluded_overrides) : src_value # Recurse if both are Hash
      end
      base
    when ::Array
      return override unless base.is_a?(::Array)
      base |= override
      base
    when ::String, ::Integer, ::Time, ::TrueClass, ::FalseClass, ::Symbol
      boolean_or ? base || override : override
    else
      throw "Implementation for deep merge of type #{override.class} is missing."
    end
  end

  # Identifies what keys in the comparison hash are missing from base hash.
  # Optionally keep the values from the comparison hash, otherwise assigns the missing keys a value of :missing_key
  def deep_diff_by_key(base, comparison, keep_values: false)
    missing_keys = {}
    if comparison.is_a?(::Hash)
      compared_keys = base.is_a?(::Hash) ? comparison.keys - base.keys : comparison.keys # Determine what keys the comparison has that the base doesn't
      compared_keys.each { |k| missing_keys[k] = keep_values ? comparison[k] : :missing_key } # Save the missing keys
      comparison.each do |k, v|
        missing_keys[k] = deep_diff_by_key(base[k], v, keep_values: keep_values) if v.is_a?(::Hash) # Recurse to find more missing keys if the hash goes deeper
      end
    end
    missing_keys.reject { |_k, v| v.is_a?(::Hash) && v.empty? } # Remove any empty hashes as there were no missing keys in them
  end

  # Deep diff two structures
  # For a hash, returns keys found in both hashes where the values don't match.
  # If a key exists in the base, but NOT the comparison, it is NOT considered a difference so that it can be a one way comparison.
  # For an array, returns an array with values found in the comparison array but not in the base array.
  def deep_diff(base, comparison, existing_keys_only: false)
    if base.nil? # if base is nil, entire comparison object is different
      return {} if comparison.nil?
      return comparison.is_a?(Hash) ? comparison.dup : comparison
    end

    case comparison
    when nil
      {}
    when ::Hash
      differing_values = {}
      base = base.dup
      comparison.each do |src_key, src_value|
        next if existing_keys_only && base.is_a?(::Hash) && !base.keys.include?(src_key)
        difference = deep_diff(base[src_key], src_value, existing_keys_only: existing_keys_only)
        differing_values[src_key] = difference unless difference == :no_diff
      end
      differing_values.reject { |_k, v| v.is_a?(::Hash) && v.empty? }
    when ::Array
      return comparison unless base.is_a?(::Array)
      difference = comparison - base
      difference.empty? ? :no_diff : difference
    else
      base == comparison ? :no_diff : comparison
    end
  end

  # Reject hash keys however deep they are. Provide a block and if it evaluates to true for a given key/value pair, it will be rejected.
  def deep_reject(hash, &block)
    hash.each_with_object({}) do |(k, v), h|
      next if yield(k, v) # reject the current key/value pair by skipping it if the block given evaluates to true
      h[k] = v.is_a?(::Hash) ? deep_reject(v, &block) : v # recursively go up the hash tree or keep the value if it's not a hash.
    end
  end

  # Reject hash keys however deep they are. Provide a block and if it evaluates to true for a given key/value pair, it will be rejected.
  def deep_select(hash, &block)
    hash.each_with_object({}) do |(k, v), h|
      if v.is_a?(::Hash)
        h[k] = deep_select(v, &block)
        h.delete(k) if h[k].is_a?(::Hash) && h[k].empty?
        next
      end
      next unless yield(k, v) # skip the current key/value pair unless the block given evaluates to true
      h[k] = v
    end
  end

  # Deep diff two Hashes
  # Remove any keys in the first hash also contained in the second hash
  # If a key exists in the base, but NOT the comparison, it is kept.
  def deep_reject_by_hash(base, comparison)
    return nil if base.nil?

    case comparison
    when ::Hash
      return base unless base.is_a?(::Hash) # if base is not a hash but the comparison is, return the base
      base = base.dup
      comparison.each do |src_key, src_value|
        base[src_key] = deep_reject_by_hash(base[src_key], src_value) # recurse to the leaf
        base[src_key] = nil if base[src_key].is_a?(::Hash) && base[src_key].empty? # set leaves to nil if they are empty hashes
      end
      base.reject { |_k, v| v.nil? } # reject any leaves that were set to nil
    else # rubocop:disable Style/EmptyElse - for clarity
      nil # drop the value if we have reached a leaf in the comparison hash
    end
  end

  def reject_keys_with_nil_values(base)
    deep_reject(base) { |_k, v| v.nil? }
  end

  def safe_value(hash, *keys)
    return nil if hash.nil? || hash[keys.first].nil?
    return hash[keys.first] if keys.length == 1 # return the value if we have reached the final key
    safe_value(hash[keys.shift], *keys) # recurse until we have reached the final key
  end

  def reject_value?(value, rejected_values)
    return false if rejected_values == :disabled

    rejected_values = [rejected_values] if rejected_values.is_a?(String) || !rejected_values.is_a?(::Array)
    rejected_values.each do |rejected_value|
      case rejected_value
      when Regexp
        next if value.is_a?(::Hash) || value.is_a?(::Array) # Don't evaluate regexp on Hash or Array
        return true if (value.to_s =~ rejected_value) == 0
      else
        return true if value == rejected_value
      end
    end
    false
  end

  def select_value?(value, selected_values)
    return true if selected_values == :disabled || selected_values.nil? || selected_values.empty?

    selected_values = [selected_values] if selected_values.is_a?(String) || !selected_values.is_a?(::Array)
    selected_values.each do |selected_value|
      case selected_value
      when Regexp
        next if value.is_a?(::Hash) || value.is_a?(::Array) # Don't evaluate regexp on Hash or Array
        return true if (value.to_s =~ selected_value) == 0
      else
        return true if value == selected_value
      end
    end
    false
  end
end
