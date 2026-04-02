<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useStore } from 'vuex';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConversationApi from 'dashboard/api/conversations';
import { MESSAGE_TYPE } from 'shared/constants/messages';

const props = defineProps({
  contactId: {
    type: [String, Number],
    required: true,
  },
  conversationId: {
    type: [String, Number],
    required: true,
  },
});

const store = useStore();

const expandedConversations = ref({});
const isLoadingMessages = ref({});
const messagesByConversation = ref({});

const uiFlags = computed(
  () => store.getters['contactConversations/getUIFlags']
);

const conversations = computed(() =>
  store.getters['contactConversations/getContactConversation'](props.contactId)
);

const previousConversations = computed(() =>
  conversations.value.filter(
    conversation => conversation.id !== Number(props.conversationId)
  )
);

const formatDateTime = timestamp => {
  if (!timestamp) return '';

  return new Intl.DateTimeFormat(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(timestamp * 1000));
};

const buildConversationRange = conversation => {
  const startAt = conversation.created_at;
  const endAt = conversation.last_activity_at || conversation.created_at;

  if (!startAt) return `#${conversation.id}`;
  if (!endAt || startAt === endAt) {
    return `#${conversation.id} · ${formatDateTime(startAt)}`;
  }

  return `#${conversation.id} · ${formatDateTime(startAt)} - ${formatDateTime(
    endAt
  )}`;
};

const getMessageBody = message =>
  message.processed_message_content || message.content || '';

const isActivityMessage = message =>
  Number(message.message_type) === MESSAGE_TYPE.ACTIVITY;

const isOutgoingMessage = message =>
  [MESSAGE_TYPE.OUTGOING, MESSAGE_TYPE.TEMPLATE].includes(
    Number(message.message_type)
  );

const fetchConversationPages = async (conversationId, before, pages = []) => {
  const { data } = await ConversationApi.getMessages(conversationId, {
    ...(before ? { before } : {}),
  });
  const payload = data.payload || [];

  if (!payload.length) {
    return pages;
  }

  return fetchConversationPages(conversationId, payload[0].id, [
    payload,
    ...pages,
  ]);
};

const loadMessages = async conversationId => {
  isLoadingMessages.value = {
    ...isLoadingMessages.value,
    [conversationId]: true,
  };

  try {
    const pages = await fetchConversationPages(conversationId);

    messagesByConversation.value = {
      ...messagesByConversation.value,
      [conversationId]: pages.flat(),
    };
  } finally {
    isLoadingMessages.value = {
      ...isLoadingMessages.value,
      [conversationId]: false,
    };
  }
};

const toggleConversation = async conversationId => {
  const isOpen = expandedConversations.value[conversationId];

  expandedConversations.value = {
    ...expandedConversations.value,
    [conversationId]: !isOpen,
  };

  if (isOpen || messagesByConversation.value[conversationId]) {
    return;
  }

  await loadMessages(conversationId);
};

const resetExpandedState = () => {
  expandedConversations.value = {};
  isLoadingMessages.value = {};
  messagesByConversation.value = {};
};

watch(
  () => props.contactId,
  (newContactId, prevContactId) => {
    if (!newContactId || newContactId === prevContactId) {
      return;
    }

    resetExpandedState();
    store.dispatch('contactConversations/get', newContactId);
  }
);

onMounted(() => {
  store.dispatch('contactConversations/get', props.contactId);
});
</script>

<template>
  <div v-if="!uiFlags.isFetching">
    <div
      v-if="!previousConversations.length"
      class="mb-4 px-4 py-3 text-sm text-n-slate-11"
    >
      {{ $t('CONTACT_PANEL.CONVERSATIONS.NO_RECORDS_FOUND') }}
    </div>

    <div v-else class="flex flex-col gap-2">
      <div
        v-for="conversation in previousConversations"
        :key="conversation.id"
        class="overflow-hidden rounded-xl border border-n-alpha-2 bg-n-background-2"
      >
        <button
          type="button"
          class="flex w-full items-start justify-between gap-3 px-4 py-3 text-left hover:bg-n-alpha-1"
          :aria-expanded="!!expandedConversations[conversation.id]"
          @click="toggleConversation(conversation.id)"
        >
          <div class="min-w-0 flex-1">
            <div class="truncate text-sm font-medium text-n-slate-12">
              {{ buildConversationRange(conversation) }}
            </div>
            <div class="mt-1 truncate text-xs text-n-slate-11">
              {{
                conversation.messages?.[0]?.processed_message_content ||
                conversation.messages?.[0]?.content ||
                ''
              }}
            </div>
          </div>
          <div class="pt-0.5 text-xs text-n-slate-11">
            <span v-if="isLoadingMessages[conversation.id]">
              <Spinner class="h-4 w-4" />
            </span>
            <Icon
              v-else
              :icon="
                expandedConversations[conversation.id]
                  ? 'i-lucide-chevron-up'
                  : 'i-lucide-chevron-down'
              "
              class="size-4"
            />
          </div>
        </button>

        <div
          v-if="expandedConversations[conversation.id]"
          class="border-t border-n-alpha-2 bg-n-background px-3 py-3"
        >
          <div
            v-if="isLoadingMessages[conversation.id]"
            class="flex items-center justify-center py-5"
          >
            <Spinner />
          </div>

          <div v-else class="flex flex-col gap-2">
            <div
              v-for="message in messagesByConversation[conversation.id] || []"
              :key="message.id"
            >
              <div
                v-if="isActivityMessage(message)"
                class="px-2 py-1 text-center text-xs text-n-slate-11"
              >
                {{ getMessageBody(message) }}
              </div>

              <div
                v-else
                class="flex"
                :class="
                  isOutgoingMessage(message) ? 'justify-end' : 'justify-start'
                "
              >
                <div
                  class="max-w-[90%] rounded-2xl px-3 py-2"
                  :class="
                    isOutgoingMessage(message)
                      ? 'bg-n-brand/10 text-n-slate-12'
                      : 'bg-n-alpha-2 text-n-slate-12'
                  "
                >
                  <div class="whitespace-pre-wrap break-words text-sm">
                    {{ getMessageBody(message) }}
                  </div>
                  <div class="mt-1 text-[11px] text-n-slate-11">
                    {{ formatDateTime(message.created_at) }}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <div v-else class="flex items-center justify-center py-5">
    <Spinner />
  </div>
</template>
