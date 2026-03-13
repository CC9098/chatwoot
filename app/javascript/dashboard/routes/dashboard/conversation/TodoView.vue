<script setup>
import { computed, onMounted, watch } from 'vue';
import { useWindowSize } from '@vueuse/core';
import { onBeforeRouteLeave, useRoute } from 'vue-router';

import CmdBarConversationSnooze from 'dashboard/routes/dashboard/commands/CmdBarConversationSnooze.vue';
import ConversationBox from 'dashboard/components/widgets/conversation/ConversationBox.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';
import SidepanelSwitch from 'dashboard/components-next/Conversation/SidepanelSwitch.vue';

import { useUISettings } from 'dashboard/composables/useUISettings';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

import TodoList from './TodoList.vue';

const props = defineProps({
  conversationId: {
    type: [String, Number],
    default: 0,
  },
});

const route = useRoute();
const store = useStore();
const { uiSettings } = useUISettings();
const { width } = useWindowSize();

const currentChat = useMapGetter('getSelectedChat');
const getConversationById = useMapGetter('getConversationById');

const isMobileLayout = computed(() => width.value < 1024);

const showConversationList = computed(() => {
  return !props.conversationId || !isMobileLayout.value;
});

const showMessageView = computed(() => {
  return !!props.conversationId || !isMobileLayout.value;
});

const isFocusedConversationView = computed(() => {
  return isMobileLayout.value && !!props.conversationId;
});

const shouldShowSidebar = computed(() => {
  if (!currentChat.value.id) {
    return false;
  }

  return uiSettings.value.is_contact_sidebar_open;
});

const messageId = computed(() => route.query.messageId);

const maybeLoadMessageContext = async conversationId => {
  const selectedConversation = getConversationById.value(conversationId);
  const firstLoadedMessageId = selectedConversation?.messages?.[0]?.id;
  const hasTargetMessageLoaded = selectedConversation?.messages?.some(
    message => {
      return Number(message.id) === Number(messageId.value);
    }
  );

  if (
    messageId.value &&
    firstLoadedMessageId &&
    !hasTargetMessageLoaded &&
    Number(messageId.value) < Number(firstLoadedMessageId)
  ) {
    await store.dispatch('fetchPreviousMessages', {
      after: messageId.value,
      before: firstLoadedMessageId,
      conversationId,
    });
  }

  if (messageId.value) {
    emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, {
      messageId: messageId.value,
    });
  }
};

const ensureConversationLoaded = async () => {
  const conversationId = Number(props.conversationId);

  if (!conversationId) {
    store.dispatch('clearSelectedState');
    return;
  }

  let selectedConversation = getConversationById.value(conversationId);

  if (!selectedConversation) {
    await store.dispatch('getConversation', conversationId);
    selectedConversation = getConversationById.value(conversationId);
  }

  if (!selectedConversation) {
    return;
  }

  if (currentChat.value.id !== conversationId) {
    await store.dispatch('setActiveChat', {
      data: selectedConversation,
      after: messageId.value,
    });
    return;
  }

  await maybeLoadMessageContext(conversationId);
};

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('portals/index');
  store.dispatch('setActiveInbox', 0);
  ensureConversationLoaded();
});

watch(
  () => props.conversationId,
  () => {
    ensureConversationLoaded();
  }
);

watch(
  () => route.query.messageId,
  () => {
    if (Number(props.conversationId) === currentChat.value.id) {
      maybeLoadMessageContext(currentChat.value.id);
    }
  }
);

onBeforeRouteLeave(() => {
  if (props.conversationId) {
    store.dispatch('clearSelectedState');
  }
});
</script>

<template>
  <section class="flex h-full w-full min-w-0">
    <TodoList :show-conversation-list="showConversationList" />
    <ConversationBox
      v-if="showMessageView"
      :inbox-id="0"
      :is-on-expanded-layout="isFocusedConversationView"
    >
      <SidepanelSwitch v-if="currentChat.id" />
    </ConversationBox>
    <ConversationSidebar v-if="shouldShowSidebar" :current-chat="currentChat" />
    <CmdBarConversationSnooze />
  </section>
</template>
