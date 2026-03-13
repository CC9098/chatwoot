/* global axios */
import ApiClient from './ApiClient';

class TodosApi extends ApiClient {
  constructor() {
    super('todos', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }
}

export default new TodosApi();
