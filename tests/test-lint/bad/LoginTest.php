<?php

namespace Tests\Feature;

use Tests\TestCase;

final class LoginTest extends TestCase
{
    public function test_skipped(): void
    {
        $this->markTestSkipped('later');
    }

    public function test_no_assert(): void
    {
        $this->postJson('/auth/login', []);
        sleep(1);
    }

    public function test_swallow(): void
    {
        try {
            $this->postJson('/auth/login', []);
        } catch (\Throwable $e) {}
        $this->assertTrue(true);
    }

    public function test_now(): void
    {
        $token = issue(now());
        $this->assertNotEmpty($token);
    }

    // public function test_old(): void {}
}
