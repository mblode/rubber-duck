export function createStore(reducer, initialState) {
  let state = initialState;
  const listeners = new Set();

  return {
    dispatch(action) {
      state = reducer(state, action);
      for (const listener of listeners) {
        listener(state);
      }
      return action;
    },
    getState() {
      return state;
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
  };
}
