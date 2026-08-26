<script lang="ts">
  import { goto } from '$app/navigation';
  import { onMount } from 'svelte';

  onMount(() => {
    goto('/game');
  });
</script>

<div class="loading">
  <h1>CAPS</h1>
  <p>Loading game...</p>
</div>

<style>
  .loading {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100vh;
    background: #1a1a2e;
    color: #e0e0e0;
    font-family: system-ui, sans-serif;
  }
  h1 {
    margin: 0;
    font-size: 3rem;
    letter-spacing: 0.2em;
    color: #e94560;
  }
  p {
    margin-top: 1rem;
    opacity: 0.7;
  }
</style>
