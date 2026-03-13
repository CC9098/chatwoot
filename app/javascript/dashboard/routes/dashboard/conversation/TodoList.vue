<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';

import Avatar from 'next/avatar/Avatar.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';

import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStore } from 'dashboard/composables/store';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
import TodosApi from 'dashboard/api/todos';
import {
  parsePrivateNoteSections,
  togglePrivateNoteTodo,
} from 'dashboard/helper/privateNoteTodoHelper';

defineProps({
  showConversationList: {
    type: Boolean,
    default: true,
  },
});

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();
const { accountId } = useAccount();

const isLoading = ref(true);
const isRefreshing = ref(false);
const notes = ref([]);
const searchQuery = ref('');
const showCompleted = ref(false);
const savingItems = ref({});

const allTodoItems = computed(() => {
  return notes.value.flatMap(note => {
    const sections = parsePrivateNoteSections(note.content);
    const textSections = sections
      .filter(section => section.type === 'text')
      .map(section => section.content.trim())
      .filter(Boolean);

    return sections
      .filter(section => section.type === 'tasks')
      .flatMap(section =>
        section.items.map(item => ({
          id: `${note.id}-${item.lineIndex}`,
          checked: item.checked,
          context: textSections[0] || '',
          label: item.label,
          lineIndex: item.lineIndex,
          note,
        }))
      );
  });
});

const openTodoCount = computed(() => {
  return allTodoItems.value.filter(item => !item.checked).length;
});

const completedTodoCount = computed(() => {
  return allTodoItems.value.filter(item => item.checked).length;
});

const summaryCards = computed(() => {
  return [
    {
      key: 'open',
      label: t('CONVERSATION.TODOS.SUMMARY.OPEN_ITEMS'),
      value: openTodoCount.value,
    },
    {
      key: 'done',
      label: t('CONVERSATION.TODOS.SUMMARY.DONE_ITEMS'),
      value: completedTodoCount.value,
    },
    {
      key: 'notes',
      label: t('CONVERSATION.TODOS.SUMMARY.NOTES'),
      value: notes.value.length,
    },
  ];
});

const normalizedSearchQuery = computed(() => {
  return searchQuery.value.trim().toLowerCase();
});

const filteredTodoItems = computed(() => {
  return allTodoItems.value
    .filter(item => showCompleted.value || !item.checked)
    .filter(item => {
      if (!normalizedSearchQuery.value) {
        return true;
      }

      const searchableFields = [
        item.label,
        item.context,
        item.note.conversation.meta.sender?.name,
        item.note.conversation.meta.assignee?.name,
        item.note.conversation.inbox.name,
        item.note.sender?.name,
        `#${item.note.conversation.id}`,
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();

      return searchableFields.includes(normalizedSearchQuery.value);
    })
    .sort((left, right) => {
      if (left.checked !== right.checked) {
        return Number(left.checked) - Number(right.checked);
      }

      return right.note.updated_at - left.note.updated_at;
    });
});

const hasTodoNotes = computed(() => notes.value.length > 0);

const emptyStateTitle = computed(() => {
  if (!hasTodoNotes.value) {
    return t('CONVERSATION.TODOS.EMPTY.TITLE');
  }

  return t('CONVERSATION.TODOS.EMPTY.FILTERED_TITLE');
});

const emptyStateMessage = computed(() => {
  if (!hasTodoNotes.value) {
    return t('CONVERSATION.TODOS.EMPTY.MESSAGE');
  }

  return t('CONVERSATION.TODOS.EMPTY.FILTERED_MESSAGE');
});

const activeTodoKey = computed(() => {
  const { conversationId } = route.params;
  const { messageId, todoLine } = route.query;

  if (!conversationId || !messageId) {
    return '';
  }

  if (todoLine !== undefined) {
    return `${messageId}-${todoLine}`;
  }

  return `${messageId}`;
});

const itemConversationRoute = item => ({
  name: 'conversation_through_todos',
  params: {
    accountId: accountId.value,
    conversationId: item.note.conversation.id,
  },
  query: {
    messageId: item.note.id,
    todoLine: item.lineIndex,
  },
});

const formatTodoLabel = label => {
  return new MessageFormatter(label, false, true).formattedMessage
    .replace(/^<p>/, '')
    .replace(/<\/p>\s*$/, '');
};

const relativeTime = timestamp => {
  return shortTimestamp(dynamicTime(timestamp), true);
};

const assigneeAndInboxLabel = item => {
  return t('CONVERSATION.TODOS.ASSIGNEE_AND_INBOX', {
    assignee:
      item.note.conversation.meta.assignee?.name ||
      t('CONVERSATION.TODOS.UNASSIGNED'),
    inbox: item.note.conversation.inbox.name,
  });
};

const isActiveItem = item => {
  if (!activeTodoKey.value) {
    return false;
  }

  return (
    activeTodoKey.value === `${item.note.id}-${item.lineIndex}` ||
    activeTodoKey.value === `${item.note.id}`
  );
};

const setNotes = todoNotes => {
  notes.value = todoNotes;
};

const replaceNote = updatedNote => {
  notes.value = notes.value.map(note => {
    return note.id === updatedNote.id ? updatedNote : note;
  });
};

const fetchTodos = async ({ silent = false } = {}) => {
  if (silent) {
    isRefreshing.value = true;
  } else {
    isLoading.value = true;
  }

  try {
    const {
      data: { payload },
    } = await TodosApi.get();
    setNotes(payload);
  } catch (error) {
    useAlert(t('CONVERSATION.TODOS.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
    isRefreshing.value = false;
  }
};

const openTodoItem = (item, event) => {
  const targetRoute = itemConversationRoute(item);
  const resolvedRoute = router.resolve(targetRoute);

  if (event.metaKey || event.ctrlKey) {
    window.open(
      `${window.chatwootConfig.hostURL}${resolvedRoute.fullPath}`,
      '_blank',
      'noopener,noreferrer'
    );
    return;
  }

  router.push(targetRoute);
};

const onTodoRowKeyDown = (item, event) => {
  if (!['Enter', ' '].includes(event.key)) {
    return;
  }

  event.preventDefault();
  openTodoItem(item, event);
};

const toggleTodoItem = async item => {
  const rowKey = `${item.note.id}-${item.lineIndex}`;

  if (savingItems.value[rowKey]) {
    return;
  }

  const updatedContent = togglePrivateNoteTodo(
    item.note.content,
    item.lineIndex
  );

  if (updatedContent === item.note.content) {
    return;
  }

  const originalNote = item.note;
  const updatedNote = {
    ...originalNote,
    content: updatedContent,
    updated_at: Math.floor(Date.now() / 1000),
  };

  savingItems.value = {
    ...savingItems.value,
    [rowKey]: true,
  };
  replaceNote(updatedNote);

  try {
    await store.dispatch('updatePrivateNote', {
      conversationId: item.note.conversation.id,
      messageId: item.note.id,
      content: updatedContent,
    });
  } catch (error) {
    replaceNote(originalNote);
    useAlert(t('CONVERSATION.PRIVATE_NOTES.TODO.UPDATE_ERROR'));
  } finally {
    savingItems.value = Object.fromEntries(
      Object.entries(savingItems.value).filter(([key]) => key !== rowKey)
    );
  }
};

onMounted(() => {
  fetchTodos();
});
</script>

<template>
  <aside
    v-show="showConversationList"
    class="flex h-full w-full min-w-0 shrink-0 flex-col border-r border-n-weak bg-n-surface-1 md:max-w-[28rem] xl:max-w-[32rem]"
  >
    <div class="border-b border-n-weak px-4 py-4">
      <div class="mb-4 flex items-start justify-between gap-3">
        <div class="min-w-0">
          <h1 class="text-base font-semibold text-n-slate-12">
            {{ $t('CONVERSATION.TODOS.TITLE') }}
          </h1>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ $t('CONVERSATION.TODOS.SUBTITLE') }}
          </p>
        </div>
        <button
          type="button"
          class="rounded-lg px-2 py-1 text-xs font-medium text-n-slate-11 transition-colors duration-200 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :disabled="isRefreshing"
          @click="fetchTodos({ silent: true })"
        >
          {{ $t('CONVERSATION.TODOS.REFRESH') }}
        </button>
      </div>

      <div class="grid grid-cols-3 gap-2">
        <div
          v-for="card in summaryCards"
          :key="card.key"
          class="rounded-xl border border-n-weak bg-n-alpha-2 px-3 py-3"
        >
          <p
            class="text-[11px] font-medium uppercase tracking-[0.08em] text-n-slate-10"
          >
            {{ card.label }}
          </p>
          <p class="mt-2 text-lg font-semibold text-n-slate-12">
            {{ card.value }}
          </p>
        </div>
      </div>

      <div class="mt-4 flex items-center gap-3">
        <Input
          v-model="searchQuery"
          :placeholder="$t('CONVERSATION.TODOS.SEARCH_PLACEHOLDER')"
          custom-input-class="!bg-n-surface-1"
        />
      </div>

      <div
        class="mt-4 flex items-center justify-between rounded-xl bg-n-alpha-2 px-3 py-2"
      >
        <div>
          <p class="text-sm font-medium text-n-slate-12">
            {{ $t('CONVERSATION.TODOS.SHOW_COMPLETED') }}
          </p>
          <p class="text-xs text-n-slate-10">
            {{ $t('CONVERSATION.TODOS.SHOW_COMPLETED_HINT') }}
          </p>
        </div>
        <Switch v-model="showCompleted" />
      </div>
    </div>

    <div class="min-h-0 flex-1 overflow-y-auto px-3 py-3">
      <div v-if="isLoading" class="flex h-full items-center justify-center">
        <Spinner />
      </div>

      <div v-else-if="filteredTodoItems.length" class="flex flex-col gap-2">
        <div
          v-for="item in filteredTodoItems"
          :key="item.id"
          class="rounded-2xl border px-3 py-3 transition-all duration-200 cursor-pointer focus:outline-none focus:ring-2 focus:ring-n-brand/20"
          :class="{
            'border-n-brand/30 bg-n-alpha-2 shadow-sm': isActiveItem(item),
            'border-n-weak bg-n-surface-1 hover:border-n-slate-5 hover:bg-n-alpha-2/70':
              !isActiveItem(item),
            'opacity-70': savingItems[item.id],
          }"
          role="button"
          tabindex="0"
          @click="event => openTodoItem(item, event)"
          @keydown="event => onTodoRowKeyDown(item, event)"
        >
          <div class="flex items-start gap-3">
            <Checkbox
              :model-value="item.checked"
              :disabled="savingItems[item.id]"
              class="mt-1 flex-shrink-0"
              @update:model-value="() => toggleTodoItem(item)"
              @click.stop
            />

            <div class="min-w-0 flex-1">
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <div
                    v-dompurify-html="formatTodoLabel(item.label)"
                    class="prose prose-sm prose-bubble max-w-none break-words text-sm [&_p]:!my-0"
                    :class="{
                      'line-through text-n-slate-10 [&_a]:text-n-slate-10':
                        item.checked,
                    }"
                  />

                  <p
                    v-if="item.context"
                    class="mt-2 line-clamp-2 text-xs text-n-slate-10"
                  >
                    {{ item.context }}
                  </p>
                </div>

                <div class="text-right text-[11px] text-n-slate-10">
                  <p>
                    {{
                      $t('CONVERSATION.TODOS.CONVERSATION_ID', {
                        id: item.note.conversation.id,
                      })
                    }}
                  </p>
                  <p class="mt-1 whitespace-nowrap">
                    {{ relativeTime(item.note.updated_at) }}
                  </p>
                </div>
              </div>

              <div class="mt-3 flex items-center gap-2">
                <Avatar
                  :name="item.note.conversation.meta.sender.name"
                  :src="item.note.conversation.meta.sender.thumbnail"
                  :size="24"
                  hide-offline-status
                  rounded-full
                />

                <div class="min-w-0">
                  <p class="truncate text-sm font-medium text-n-slate-12">
                    {{ item.note.conversation.meta.sender.name }}
                  </p>
                  <p class="truncate text-xs text-n-slate-10">
                    {{ assigneeAndInboxLabel(item) }}
                  </p>
                </div>
              </div>

              <div
                class="mt-3 flex flex-wrap gap-2 text-[11px] text-n-slate-10"
              >
                <span class="rounded-full bg-n-alpha-2 px-2 py-1">
                  {{
                    item.note.sender?.name ||
                    $t('CONVERSATION.TODOS.UNKNOWN_AUTHOR')
                  }}
                </span>
                <span
                  v-if="item.note.conversation.meta.team?.name"
                  class="rounded-full bg-n-alpha-2 px-2 py-1"
                >
                  {{ item.note.conversation.meta.team.name }}
                </span>
                <span class="rounded-full bg-n-alpha-2 px-2 py-1 capitalize">
                  {{ item.note.conversation.status }}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <EmptyState
        v-else
        :title="emptyStateTitle"
        :message="emptyStateMessage"
      />
    </div>
  </aside>
</template>
