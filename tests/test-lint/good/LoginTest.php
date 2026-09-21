<?php

declare(strict_types=1);

namespace Tests\Feature;

use Illuminate\Support\Carbon;
use Tests\TestCase;

final class LoginTest extends TestCase
{
    /** TC-001 */
    public function test_login_with_correct_credentials_returns_200(): void
    {
        Carbon::setTestNow('2026-01-01');
        $user = User::factory()->create(['password' => 'correct-horse']);
        $res = $this->postJson('/auth/login', ['email' => $user->email, 'password' => 'correct-horse']);
        $res->assertStatus(200)->assertJsonStructure(['token']);
    }

    /** TC-002 */
    public function test_login_with_wrong_password_returns_401(): void
    {
        $user = User::factory()->create();
        $res = $this->postJson('/auth/login', ['email' => $user->email, 'password' => 'x']);
        $res->assertStatus(401)->assertJsonPath('error.code', 'INVALID_CREDENTIALS');
    }
}
